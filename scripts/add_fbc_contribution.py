#!/usr/bin/env python3
"""
Add FBC Contribution Task Script

This script creates internal requests to add FBC contributions to index images.
It batches multiple fragments into a single IIB request and splits requests
according to their OCP versions.

The script is organized into three processing phases:
1. prepare_inputs: validates inputs, groups components by OCP version, writes config
2. process_ocp_groups: executes IIB requests per OCP group with batching and retries
3. collect_and_deduplicate: aggregates results, deduplicates, produces final output

This script is intended to be placed in the release-service-utils repo at:
/home/scripts/python/tasks/managed/add_fbc_contribution.py
"""

import argparse
import atexit
import base64
import gzip
import json
import logging
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
)
logger = logging.getLogger(__name__)

class TaskError(Exception):
    """Exception raised for task failures that should be recorded in results."""

    pass


class ResultWriter:
    """Manages writing task results to the Tekton result file."""

    def __init__(self, result_path: str):
        self.result_path = result_path
        self.status = "Failure"
        self.error_message = ""
        atexit.register(self._write_result)

    def _write_result(self) -> None:
        """Write the final result to the Tekton result file. Called via atexit."""
        try:
            with open(self.result_path, "w") as f:
                f.write(self.status)
        except OSError as e:
            logger.error(f"Failed to write result file: {e}")

    def set_success(self) -> None:
        """Mark the task as successful."""
        self.status = "Success"

    def set_failure(self, message: str) -> None:
        """Mark the task as failed with an error message."""
        self.status = "Failure"
        self.error_message = message


@dataclass
class Config:
    """Configuration for FBC contribution processing."""

    build_timeout_seconds: int
    request_timeout_seconds: int
    internal_request_service_account: str
    publishing_credentials: str
    iib_service_account_secret: str
    must_publish_index_image: str
    must_overwrite_from_index_image: str
    build_tags: list[str]
    add_arches: list[str]
    ocp_versions: list[str]
    total_components: int
    max_batch_size: int
    pipeline_timeout: str
    task_timeout: str
    groups_dir: str
    results_file: str
    is_staged: bool


def positive_int(value: str) -> int:
    """Validate that value is a positive integer."""
    try:
        ivalue = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid int value: '{value}'")
    if ivalue <= 0:
        raise argparse.ArgumentTypeError(
            f"must be a positive integer, got: {ivalue}"
        )
    return ivalue


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Add FBC contributions to index images",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--data-dir",
        required=True,
        help="The location where data is stored",
    )
    parser.add_argument(
        "--data-path",
        required=True,
        help="Path to the JSON string of the merged data in the data workspace",
    )
    parser.add_argument(
        "--snapshot-path",
        required=True,
        help="Path to the JSON string of the mapped Snapshot spec in the data workspace",
    )
    parser.add_argument(
        "--pipeline-run-uid",
        required=True,
        help="The uid of the current pipelineRun",
    )
    parser.add_argument(
        "--task-run-uid",
        required=True,
        help="The uid of the current taskRun",
    )
    parser.add_argument(
        "--results-dir-path",
        required=True,
        help="Path to the results directory in the data workspace",
    )
    parser.add_argument(
        "--task-git-url",
        required=True,
        help="The url to the git repo where the release-service-catalog tasks are stored",
    )
    parser.add_argument(
        "--task-git-revision",
        required=True,
        help="The revision in the taskGitUrl repo to be used",
    )
    parser.add_argument(
        "--max-batch-size",
        type=positive_int,
        default=5,
        help="Maximum number of FBC fragments to process in a single batch",
    )
    parser.add_argument(
        "--must-publish-index-image",
        required=True,
        help="Whether the index image should be published",
    )
    parser.add_argument(
        "--must-overwrite-from-index-image",
        required=True,
        help="Whether to overwrite the from index image",
    )
    parser.add_argument(
        "--iib-service-account-secret",
        required=True,
        help="IIB service account secret name",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=3,
        help="Maximum number of retry attempts for failed internal requests",
    )
    parser.add_argument(
        "--batch-retry-delay-seconds",
        type=int,
        default=60,
        help="Delay between batch retry attempts in seconds",
    )
    parser.add_argument(
        "--request-results-file-path",
        required=True,
        help="Path to write the request results file location",
    )
    parser.add_argument(
        "--internal-request-results-file-path",
        required=True,
        help="Path to write the internal request results file location",
    )
    parser.add_argument(
        "--result-path",
        required=True,
        help="Path to write the task result (Success or Failure)",
    )

    return parser.parse_args()


def load_json_file(file_path: str) -> dict[str, Any]:
    """Load and parse a JSON file."""
    with open(file_path) as f:
        return json.load(f)


def save_json_file(file_path: str, data: dict[str, Any]) -> None:
    """Save data to a JSON file."""
    with open(file_path, "w") as f:
        json.dump(data, f, indent=2)


def run_command(
    cmd: list[str],
    capture_output: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    logger.debug(f"Running command: {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        capture_output=capture_output,
        text=True,
        check=check,
    )


def format_timeout(seconds: int) -> str:
    """Format seconds into Tekton timeout format (e.g., '1h30m0s')."""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours}h{minutes}m{secs}s"


def prepare_inputs(args: argparse.Namespace) -> Config:
    """
    Step 1: Validate inputs, read configuration, group components by OCP version,
    and return a Config object for subsequent steps.
    """
    logger.info("Starting input preparation...")

    data_file = os.path.join(args.data_dir, args.data_path)
    if not os.path.isfile(data_file):
        raise TaskError("No valid data file was provided.")

    snapshot_path = os.path.join(args.data_dir, args.snapshot_path)
    if not os.path.isfile(snapshot_path):
        raise TaskError(f"Snapshot not found at {snapshot_path}")

    results_file_relative = os.path.join(
        args.results_dir_path, "internal-requests-results.json"
    )
    with open(args.internal_request_results_file_path, "w") as f:
        f.write(results_file_relative)

    results_file = os.path.join(args.data_dir, results_file_relative)

    request_results_path = os.path.join(
        args.data_dir, args.pipeline_run_uid, f"ir-{args.task_run_uid}-result.json"
    )
    with open(args.request_results_file_path, "w") as f:
        f.write(request_results_path)

    data = load_json_file(data_file)
    snapshot = load_json_file(snapshot_path)

    default_build_timeout_seconds = 3600
    default_request_timeout_seconds = 3600

    build_timeout_seconds = int(
        data.get("fbc", {}).get("buildTimeoutSeconds", default_build_timeout_seconds)
    )
    request_timeout_seconds = int(
        data.get("fbc", {}).get(
            "requestTimeoutSeconds", default_request_timeout_seconds
        )
    )
    internal_request_service_account = data.get("fbc", {}).get(
        "internalRequestServiceAccount", "release-service-account"
    )
    publishing_credentials = data.get("fbc", {}).get(
        "publishingCredentials", "catalog-publishing-secret"
    )

    iib_service_account_secret = args.iib_service_account_secret
    must_publish_index_image = args.must_publish_index_image
    must_overwrite_from_index_image = args.must_overwrite_from_index_image

    ocp_versions_set: set[str] = set()
    components_without_ocp_version: list[str] = []
    for component in snapshot.get("components", []):
        ocp_version_list = component.get("ocpVersion", [])
        if not isinstance(ocp_version_list, list) or len(ocp_version_list) == 0:
            components_without_ocp_version.append(component.get("name", "<unknown>"))
        else:
            ocp_versions_set.update(ocp_version_list)

    if components_without_ocp_version:
        raise TaskError(
            f"The following components have missing or empty ocpVersion: "
            f"{', '.join(components_without_ocp_version)}. "
            f"All components must have at least one valid OCP version. "
            f"This may indicate a problem with prepare-fbc-snapshot."
        )

    ocp_versions = sorted(ocp_versions_set)

    logger.info(f"Found OCP versions: {' '.join(ocp_versions)}")
    logger.info("Using pre-determined values from prepare-fbc-parameters:")
    logger.info(f"  - mustPublishIndexImage: {must_publish_index_image}")
    logger.info(f"  - mustOverwriteFromIndexImage: {must_overwrite_from_index_image}")
    logger.info(f"  - iibServiceAccountSecret: {iib_service_account_secret}")

    os.makedirs(os.path.dirname(results_file), exist_ok=True)
    save_json_file(results_file, {"components": []})

    components = snapshot.get("components", [])
    if not isinstance(components, list) or len(components) == 0:
        raise TaskError("Snapshot missing required 'components' array or it's empty")

    total_components = len(components)
    logger.info(f"Found {total_components} components in snapshot")

    max_batch_size = args.max_batch_size
    logger.info(
        f"Preparing {total_components} components with maximum batch size of {max_batch_size}..."
    )

    num_batches = (total_components + max_batch_size - 1) // max_batch_size
    logger.info(f"Creating {num_batches} batch(es) for {total_components} components")

    build_tags = data.get("fbc", {}).get("buildTags", [])
    add_arches = data.get("fbc", {}).get("addArches", [])
    is_staged = data.get("fbc", {}).get("stagedIndex", False)

    finally_task_timeout = 300
    pipeline_timeout = format_timeout(request_timeout_seconds + finally_task_timeout)
    task_timeout = format_timeout(request_timeout_seconds)

    groups_dir = os.path.join(args.data_dir, "ocp-groups")
    os.makedirs(groups_dir, exist_ok=True)

    logger.info("Grouping snapshot components by OCP version")
    for ocp_version in ocp_versions:
        group_file = os.path.join(groups_dir, f"{ocp_version}.json")

        group_components = []
        for component in components:
            comp_ocp_versions = component.get("ocpVersion", [])
            if ocp_version in comp_ocp_versions:
                version_metadata = None
                for meta in component.get("ocpVersionMetadata", []):
                    if meta.get("version") == ocp_version:
                        version_metadata = meta
                        break

                new_component = component.copy()
                new_component["ocpVersion"] = ocp_version
                if version_metadata:
                    new_component["updatedFromIndex"] = version_metadata.get(
                        "updatedFromIndex"
                    )
                    new_component["targetIndex"] = version_metadata.get("targetIndex")
                new_component["originalName"] = component.get("name")

                if len(comp_ocp_versions) > 1:
                    new_component["name"] = f"{component.get('name')}-{ocp_version}"

                group_components.append(new_component)

        save_json_file(group_file, group_components)
        logger.info(
            f"OCP version {ocp_version} has {len(group_components)} component instance(s)"
        )

    state_dir = os.path.join(args.data_dir, "fbc-state")
    os.makedirs(state_dir, exist_ok=True)

    config = Config(
        build_timeout_seconds=build_timeout_seconds,
        request_timeout_seconds=request_timeout_seconds,
        internal_request_service_account=internal_request_service_account,
        publishing_credentials=publishing_credentials,
        iib_service_account_secret=iib_service_account_secret,
        must_publish_index_image=must_publish_index_image,
        must_overwrite_from_index_image=must_overwrite_from_index_image,
        build_tags=build_tags,
        add_arches=add_arches,
        ocp_versions=ocp_versions,
        total_components=total_components,
        max_batch_size=max_batch_size,
        pipeline_timeout=pipeline_timeout,
        task_timeout=task_timeout,
        groups_dir=groups_dir,
        results_file=results_file,
        is_staged=is_staged,
    )

    config_file = os.path.join(state_dir, "config.json")
    config_dict = {
        "build_timeout_seconds": str(config.build_timeout_seconds),
        "request_timeout_seconds": str(config.request_timeout_seconds),
        "internal_request_service_account": config.internal_request_service_account,
        "publishing_credentials": config.publishing_credentials,
        "iib_service_account_secret": config.iib_service_account_secret,
        "must_publish_index_image": config.must_publish_index_image,
        "must_overwrite_from_index_image": config.must_overwrite_from_index_image,
        "build_tags": config.build_tags,
        "add_arches": config.add_arches,
        "ocp_versions": " ".join(config.ocp_versions),
        "total_components": str(config.total_components),
        "max_batch_size": str(config.max_batch_size),
        "pipeline_timeout": config.pipeline_timeout,
        "task_timeout": config.task_timeout,
        "groups_dir": config.groups_dir,
        "results_file": config.results_file,
        "is_staged": str(config.is_staged).lower(),
    }
    save_json_file(config_file, config_dict)

    logger.info(f"Configuration written to {config_file}")
    return config


def execute_batch(
    args: argparse.Namespace,
    config: Config,
    batch_num: int,
    from_index: str,
    group_ocp_version: str,
    group_target_index: str,
    group_build_tags: list[str],
    batch_fragments: list[str],
) -> tuple[bool, str | None]:
    """
    Create an InternalRequest for a single batch, wait for completion,
    and write results to the results file.

    Returns:
        Tuple of (success: bool, new_index_image: str | None)
    """
    logger.info(
        f"Executing group batch {batch_num + 1}: fromIndex={from_index} "
        f"(OCP: {group_ocp_version})"
    )

    task_label = "internal-services.appstudio.openshift.io/group-id"
    pipelinerun_label = "internal-services.appstudio.openshift.io/pipelinerun-uid"

    # Include OCP version in filename to prevent collisions between groups
    output_log = os.path.join(
        args.data_dir,
        f"ir-{args.task_run_uid}-{group_ocp_version}-batch-{batch_num + 1}-output.log",
    )

    cmd = [
        "internal-request",
        "--pipeline",
        "update-fbc-catalog",
        "-p",
        f"fromIndex={from_index}",
        "-p",
        f"fbcFragments={json.dumps(batch_fragments)}",
        "-p",
        f"iibServiceAccountSecret={config.iib_service_account_secret}",
        "-p",
        f"publishingCredentials={config.publishing_credentials}",
        "-p",
        f"buildTimeoutSeconds={config.build_timeout_seconds}",
        "-p",
        f"buildTags={json.dumps(group_build_tags)}",
        "-p",
        f"addArches={json.dumps(config.add_arches)}",
        "-p",
        f"mustPublishIndexImage={config.must_publish_index_image}",
        "-p",
        f"mustOverwriteFromIndexImage={config.must_overwrite_from_index_image}",
        "-p",
        f"taskGitUrl={args.task_git_url}",
        "-p",
        f"taskGitRevision={args.task_git_revision}",
        "--service-account",
        config.internal_request_service_account,
        "-l",
        f"{task_label}={args.task_run_uid}",
        "-l",
        f"{pipelinerun_label}={args.pipeline_run_uid}",
        "--pipeline-timeout",
        config.pipeline_timeout,
        "--task-timeout",
        config.task_timeout,
        "-t",
        str(config.request_timeout_seconds),
    ]

    try:
        result = run_command(cmd, check=False)
        with open(output_log, "w") as f:
            f.write(result.stdout)
            if result.stderr:
                f.write(result.stderr)

        if result.returncode != 0:
            logger.error(f"Batch {batch_num + 1} internal-request command failed")
            return False, None

    except subprocess.SubprocessError as e:
        logger.error(f"Failed to execute internal-request: {e}")
        return False, None

    internal_request = None
    with open(output_log) as f:
        for line in f:
            if "created" in line:
                match = re.search(r"'([^']+)'", line)
                if match:
                    internal_request = match.group(1)
                    break

    if not internal_request:
        logger.error(f"Could not extract internal request name from output")
        return False, None

    try:
        result = run_command(
            [
                "kubectl",
                "get",
                "internalrequest",
                internal_request,
                "-o",
                "jsonpath={.status.conditions[?(@.type==\"Succeeded\")].status}",
            ]
        )
        request_status = result.stdout.strip()

        if request_status != "True":
            logger.error(f"Batch {batch_num + 1} internal request failed")

            reason_result = run_command(
                [
                    "kubectl",
                    "get",
                    "internalrequest",
                    internal_request,
                    "-o",
                    "jsonpath={.status.conditions[?(@.type==\"Succeeded\")].reason}",
                ]
            )
            message_result = run_command(
                [
                    "kubectl",
                    "get",
                    "internalrequest",
                    internal_request,
                    "-o",
                    "jsonpath={.status.conditions[?(@.type==\"Succeeded\")].message}",
                ]
            )
            logger.error(f"Reason: {reason_result.stdout.strip()}")
            logger.error(f"Message: {message_result.stdout.strip()}")
            return False, None

        results_output = run_command(
            [
                "kubectl",
                "get",
                "internalrequest",
                internal_request,
                "-o",
                "jsonpath={.status.results}",
            ]
        )
        results_str = results_output.stdout.strip()

        if not results_str or results_str == "{}":
            logger.error(
                f"Batch {batch_num + 1} succeeded but returned empty results"
            )
            return False, None

        results = json.loads(results_str)

    except (subprocess.SubprocessError, json.JSONDecodeError) as e:
        logger.error(f"Failed to get internal request results: {e}")
        return False, None

    # Include OCP version in filename to prevent collisions between groups
    result_file = os.path.join(
        args.data_dir,
        f"ir-{args.task_run_uid}-{group_ocp_version}-batch-{batch_num + 1}-result.json",
    )
    save_json_file(result_file, results)

    json_build_info_b64 = results.get("jsonBuildInfo", "")
    try:
        decompressed_json_build_info = json.loads(
            gzip.decompress(base64.b64decode(json_build_info_b64)).decode("utf-8")
        )
    except (ValueError, gzip.BadGzipFile) as e:
        logger.error(f"Failed to decompress jsonBuildInfo: {e}")
        return False, None

    completion_time_raw = decompressed_json_build_info.get("updated")
    if not completion_time_raw:
        logger.error("completion_time not found in IIB build info")
        return False, None

    logger.info("Extracting completion_time from IIB build info")
    logger.info(f"  Raw value: {completion_time_raw}")

    try:
        dt = datetime.fromisoformat(completion_time_raw.replace("Z", "+00:00"))
        completion_time = int(dt.timestamp())
    except ValueError as e:
        logger.error(f"Failed to parse completion_time: {completion_time_raw}")
        logger.error(f"Date conversion error: {e}")
        return False, None

    logger.info(f"  Epoch timestamp: {completion_time}")

    if not re.match(r"^\d{10}$", str(completion_time)):
        logger.error(
            f"Invalid completion_time format (expected 10 digits): {completion_time}"
        )
        return False, None

    if not group_target_index:
        target_index_with_timestamp = ""
    elif re.match(r".*\d{10}$", group_target_index):
        target_index_with_timestamp = group_target_index
    else:
        target_index_with_timestamp = f"{group_target_index}-{completion_time}"

    current_results = load_json_file(config.results_file)

    for fragment in batch_fragments:
        logger.info(
            f"Processing result for fragment: {fragment} "
            f"(group batch {batch_num + 1}, OCP: {group_ocp_version})"
        )

        index_image_digests_str = results.get("indexImageDigests", "")
        image_digests = [d for d in index_image_digests_str.split(" ") if d]

        build_result = {
            "fbc_fragment": fragment,
            "target_index": group_target_index,
            "target_index_with_timestamp": target_index_with_timestamp,
            "ocp_version": group_ocp_version,
            "image_digests": image_digests,
            "index_image": decompressed_json_build_info.get("index_image"),
            "index_image_resolved": decompressed_json_build_info.get(
                "internal_index_image_copy_resolved"
            ),
            "completion_time": str(completion_time),
            "iibLog": results.get("iibLog"),
        }

        current_results["components"].append(build_result)

    save_json_file(config.results_file, current_results)

    logger.info(
        f"Group batch {batch_num + 1} completed successfully for OCP {group_ocp_version}"
    )

    new_index_image = None
    if config.must_overwrite_from_index_image == "false":
        new_index_image = decompressed_json_build_info.get("index_image")
        if new_index_image:
            logger.info(f"Updated fromIndex for next batch: {new_index_image}")

    return True, new_index_image


def process_ocp_group(
    args: argparse.Namespace,
    config: Config,
    group_ocp_version: str,
) -> None:
    """
    Process a single OCP version group - extract parameters, execute batches,
    handle retries.
    """
    group_file = os.path.join(config.groups_dir, f"{group_ocp_version}.json")
    group_components = load_json_file(group_file)

    logger.info(f"Processing OCP group {group_ocp_version}")

    first_component = group_components[0] if group_components else {}
    group_from_index = first_component.get("updatedFromIndex", "")
    group_target_index = first_component.get("targetIndex", "")

    logger.info(
        f"Group parameters - fromIndex: {group_from_index}, "
        f"targetIndex: {group_target_index}"
    )

    group_build_tags = list(config.build_tags)
    if group_target_index:
        parts = group_target_index.rsplit(":", 1)
        if len(parts) == 2:
            group_target_tag = parts[1]
            logger.info(
                f"Using tag '{group_target_tag}' for PLR identification "
                f"in OCP group {group_ocp_version}"
            )
            group_build_tags.append(group_target_tag)
        else:
                raise TaskError(
                    f"Target index for OCP group {group_ocp_version} has no tag: "
                    f"{group_target_index}"
                )
    else:
        logger.info(
            f"No target index for OCP group {group_ocp_version} "
            "(staged release), skipping tag extraction"
        )

    logger.info(
        f"Group build tags for OCP {group_ocp_version}: {' '.join(group_build_tags)}"
    )

    group_current_from_index = group_from_index
    group_latest_iib_index_image = ""
    group_failed_batches: list[int] = []
    group_successful_batches: list[int] = []

    num_components = len(group_components)
    group_num_batches = (num_components + config.max_batch_size - 1) // config.max_batch_size

    logger.info(
        f"Creating {group_num_batches} batch(es) for {num_components} components "
        f"in OCP group {group_ocp_version}"
    )

    def get_current_from_index() -> str:
        if config.must_overwrite_from_index_image == "true":
            return group_from_index
        else:
            if not group_successful_batches:
                return group_from_index
            else:
                if not group_latest_iib_index_image:
                    raise TaskError(
                        "FATAL ERROR: Successful batches exist but "
                        "group_latest_iib_index_image is empty! "
                        f"This would cause data loss. Successful batches: "
                        f"{group_successful_batches}"
                    )
                return group_latest_iib_index_image

    def get_batch_fragments(batch_num: int) -> list[str]:
        start_idx = batch_num * config.max_batch_size
        end_idx = min((batch_num + 1) * config.max_batch_size, len(group_components))
        return [c.get("containerImage", "") for c in group_components[start_idx:end_idx]]

    for batch_num in range(group_num_batches):
        logger.info(
            f"Processing group batch {batch_num + 1}/{group_num_batches} "
            f"for OCP {group_ocp_version}..."
        )

        group_current_from_index = get_current_from_index()
        batch_fragments = get_batch_fragments(batch_num)

        success, new_index = execute_batch(
            args,
            config,
            batch_num,
            group_current_from_index,
            group_ocp_version,
            group_target_index,
            group_build_tags,
            batch_fragments,
        )

        if success:
            group_successful_batches.append(batch_num)
            logger.info(
                f"Group batch {batch_num + 1} succeeded for OCP {group_ocp_version}"
            )
            if new_index:
                group_latest_iib_index_image = new_index
        else:
            group_failed_batches.append(batch_num)
            logger.warning(
                f"Group batch {batch_num + 1} failed, will retry later "
                f"for OCP {group_ocp_version}"
            )

    for retry_attempt in range(1, args.max_retries + 1):
        if not group_failed_batches:
            logger.info(
                f"All group batches completed successfully for OCP {group_ocp_version}"
            )
            break

        logger.info(
            f"Retry attempt {retry_attempt}: {len(group_failed_batches)} group batches "
            f"to retry for OCP {group_ocp_version}"
        )

        still_failed: list[int] = []

        for batch_num in group_failed_batches:
            group_current_from_index = get_current_from_index()
            batch_fragments = get_batch_fragments(batch_num)

            success, new_index = execute_batch(
                args,
                config,
                batch_num,
                group_current_from_index,
                group_ocp_version,
                group_target_index,
                group_build_tags,
                batch_fragments,
            )

            if success:
                logger.info(
                    f"Group batch {batch_num + 1} succeeded on retry attempt "
                    f"{retry_attempt} for OCP {group_ocp_version}"
                )
                group_successful_batches.append(batch_num)
                if new_index:
                    group_latest_iib_index_image = new_index
            else:
                still_failed.append(batch_num)
                logger.warning(
                    f"Group batch {batch_num + 1} failed retry attempt "
                    f"{retry_attempt} for OCP {group_ocp_version}"
                )

        group_failed_batches = still_failed

        if group_failed_batches and retry_attempt < args.max_retries:
            logger.info(
                f"Waiting {args.batch_retry_delay_seconds} seconds before next "
                "retry attempt..."
            )
            time.sleep(args.batch_retry_delay_seconds)

    if group_failed_batches:
        failed_batch_nums = ", ".join(str(b + 1) for b in group_failed_batches)
        raise TaskError(
            f"{len(group_failed_batches)} group batches failed after all retries "
            f"for OCP {group_ocp_version}: batches {failed_batch_nums}. "
            f"Cannot proceed with partial index — this would result in incomplete "
            f"fragment coverage."
        )

    logger.info(
        f"SUCCESS: All {group_num_batches} group batches completed successfully "
        f"for OCP {group_ocp_version}"
    )


def process_ocp_groups(args: argparse.Namespace, config: Config) -> None:
    """
    Step 2: Execute IIB requests per OCP group with batching, chaining, and retries.
    """
    logger.info("Starting group processing")

    for ocp_version in config.ocp_versions:
        logger.info(f"Processing OCP group: {ocp_version}")
        process_ocp_group(args, config, ocp_version)

    logger.info("Processing completed successfully")


def collect_and_deduplicate(args: argparse.Namespace, config: Config) -> None:
    """
    Step 3: Aggregate results, deduplicate by target, and produce final output
    for downstream tasks.
    """
    logger.info("Starting collection and deduplication...")

    results = load_json_file(config.results_file)

    if config.is_staged:
        unique_keys = set(c.get("ocp_version", "") for c in results.get("components", []))
    else:
        unique_keys = set(c.get("target_index", "") for c in results.get("components", []))

    unique_targets = len(unique_keys)
    total_components = len(results.get("components", []))

    if total_components > unique_targets:
        logger.info(f"Found {total_components} components for {unique_targets} unique targets")
        logger.info("Keeping only the last (most recent) index for each OCP target")

        grouped: dict[str, dict[str, Any]] = {}
        for component in results.get("components", []):
            if config.is_staged:
                key = component.get("ocp_version", "")
            else:
                key = component.get("target_index", "") or component.get("ocp_version", "")
            grouped[key] = component

        results = {"components": list(grouped.values())}
        save_json_file(config.results_file, results)

        deduplicated_count = len(results.get("components", []))
        logger.info(f"Deduplicated from {total_components} to {deduplicated_count} components")
    else:
        logger.info(
            f"No deduplication needed ({total_components} components, "
            f"{unique_targets} unique targets)"
        )

    batch_result_files = sorted(
        Path(args.data_dir).glob(f"ir-*-batch-*-result.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )

    if not batch_result_files:
        raise TaskError("No batch result files found")

    latest_result_file = batch_result_files[0]
    latest_results = load_json_file(str(latest_result_file))

    logger.info("Final publishing and compatibility values:")
    logger.info(f"  - mustPublishIndexImage: {config.must_publish_index_image}")

    iib_log = latest_results.get("iibLog", "")
    if iib_log:
        print(iib_log)

    exit_code = int(latest_results.get("exitCode", 0))

    if config.must_publish_index_image == "true":
        logger.info("Index image will be published.")
    else:
        logger.info(
            "Index image will not be published (decision made by prepare-fbc-parameters)."
        )

    if exit_code != 0:
        raise TaskError(
            f"IIB batch processing failed with exit code {exit_code}. "
            "Check the batch logs above to understand the reason."
        )

    snapshot_path = os.path.join(args.data_dir, args.snapshot_path)
    snapshot = load_json_file(snapshot_path)
    total_components = len(snapshot.get("components", []))

    logger.info(
        f"Multi-OCP batch processing completed successfully with {total_components} "
        f"components across {len(config.ocp_versions)} OCP versions"
    )
    logger.info("Results file:")
    print(json.dumps(results, indent=2))


def main() -> None:
    """Main entry point."""
    args = parse_args()

    result_writer = ResultWriter(args.result_path)

    try:
        config = prepare_inputs(args)
        process_ocp_groups(args, config)
        collect_and_deduplicate(args, config)
        result_writer.set_success()
    except TaskError as e:
        logger.error(str(e))
        result_writer.set_failure(str(e))
    except Exception as e:
        logger.exception("Unexpected error occurred")
        result_writer.set_failure(f"Unexpected error: {e}")


if __name__ == "__main__":
    main()
