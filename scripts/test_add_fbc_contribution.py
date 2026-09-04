#!/usr/bin/env python3
"""
Unit tests for add_fbc_contribution.py

This test file is intended to be placed in the release-service-utils repo alongside
the add_fbc_contribution.py script.

Run with: pytest test_add_fbc_contribution.py -v
"""

import argparse
import base64
import gzip
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from add_fbc_contribution import (
    Config,
    ResultWriter,
    TaskError,
    collect_and_deduplicate,
    format_timeout,
    load_json_file,
    parse_args,
    positive_int,
    prepare_inputs,
    save_json_file,
)


class TestPositiveInt:
    """Tests for the positive_int argument validator."""

    def test_positive_int_valid(self):
        assert positive_int("5") == 5
        assert positive_int("1") == 1
        assert positive_int("100") == 100

    def test_positive_int_zero_raises(self):
        with pytest.raises(argparse.ArgumentTypeError) as exc_info:
            positive_int("0")
        assert "must be a positive integer" in str(exc_info.value)

    def test_positive_int_negative_raises(self):
        with pytest.raises(argparse.ArgumentTypeError) as exc_info:
            positive_int("-1")
        assert "must be a positive integer" in str(exc_info.value)

    def test_positive_int_invalid_string_raises(self):
        with pytest.raises(argparse.ArgumentTypeError) as exc_info:
            positive_int("abc")
        assert "invalid int value" in str(exc_info.value)


class TestFormatTimeout:
    """Tests for the format_timeout function."""

    def test_format_timeout_one_hour(self):
        assert format_timeout(3600) == "1h0m0s"

    def test_format_timeout_one_minute(self):
        assert format_timeout(60) == "0h1m0s"

    def test_format_timeout_complex(self):
        assert format_timeout(3665) == "1h1m5s"

    def test_format_timeout_zero(self):
        assert format_timeout(0) == "0h0m0s"

    def test_format_timeout_large_value(self):
        assert format_timeout(7200) == "2h0m0s"


class TestJsonFileOperations:
    """Tests for JSON file load/save operations."""

    def test_load_json_file(self, tmp_path):
        test_data = {"key": "value", "number": 42}
        test_file = tmp_path / "test.json"
        test_file.write_text(json.dumps(test_data))

        result = load_json_file(str(test_file))
        assert result == test_data

    def test_save_json_file(self, tmp_path):
        test_data = {"key": "value", "list": [1, 2, 3]}
        test_file = tmp_path / "output.json"

        save_json_file(str(test_file), test_data)

        with open(test_file) as f:
            result = json.load(f)
        assert result == test_data

    def test_load_json_file_not_found(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            load_json_file(str(tmp_path / "nonexistent.json"))


class TestParseArgs:
    """Tests for argument parsing."""

    def test_parse_args_required_arguments(self):
        test_args = [
            "--data-dir", "/data",
            "--data-path", "data.json",
            "--snapshot-path", "snapshot.json",
            "--pipeline-run-uid", "pipeline-123",
            "--task-run-uid", "task-456",
            "--results-dir-path", "results",
            "--task-git-url", "https://github.com/repo",
            "--task-git-revision", "main",
            "--must-publish-index-image", "true",
            "--must-overwrite-from-index-image", "false",
            "--iib-service-account-secret", "secret",
            "--request-results-file-path", "/results/request",
            "--internal-request-results-file-path", "/results/internal",
        ]

        with patch("sys.argv", ["prog"] + test_args):
            args = parse_args()

        assert args.data_dir == "/data"
        assert args.data_path == "data.json"
        assert args.snapshot_path == "snapshot.json"
        assert args.pipeline_run_uid == "pipeline-123"
        assert args.task_run_uid == "task-456"
        assert args.max_batch_size == 5  # default
        assert args.max_retries == 3  # default

    def test_parse_args_with_optional_arguments(self):
        test_args = [
            "--data-dir", "/data",
            "--data-path", "data.json",
            "--snapshot-path", "snapshot.json",
            "--pipeline-run-uid", "pipeline-123",
            "--task-run-uid", "task-456",
            "--results-dir-path", "results",
            "--task-git-url", "https://github.com/repo",
            "--task-git-revision", "main",
            "--must-publish-index-image", "true",
            "--must-overwrite-from-index-image", "false",
            "--iib-service-account-secret", "secret",
            "--request-results-file-path", "/results/request",
            "--internal-request-results-file-path", "/results/internal",
            "--max-batch-size", "10",
            "--max-retries", "5",
            "--batch-retry-delay-seconds", "120",
        ]

        with patch("sys.argv", ["prog"] + test_args):
            args = parse_args()

        assert args.max_batch_size == 10
        assert args.max_retries == 5
        assert args.batch_retry_delay_seconds == 120


class TestPrepareInputs:
    """Tests for the prepare_inputs function."""

    @pytest.fixture
    def setup_test_files(self, tmp_path):
        """Create test data files."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        data_file = {
            "fbc": {
                "buildTimeoutSeconds": 1800,
                "requestTimeoutSeconds": 1800,
                "internalRequestServiceAccount": "test-sa",
                "publishingCredentials": "test-creds",
                "buildTags": ["tag1", "tag2"],
                "addArches": ["amd64", "arm64"],
                "stagedIndex": False,
            }
        }

        snapshot_file = {
            "components": [
                {
                    "name": "component-1",
                    "containerImage": "quay.io/test/image1:v1",
                    "ocpVersion": ["v4.17", "v4.18"],
                    "ocpVersionMetadata": [
                        {
                            "version": "v4.17",
                            "updatedFromIndex": "registry.io/index:v4.17",
                            "targetIndex": "registry.io/target:v4.17-1234567890",
                        },
                        {
                            "version": "v4.18",
                            "updatedFromIndex": "registry.io/index:v4.18",
                            "targetIndex": "registry.io/target:v4.18-1234567890",
                        },
                    ],
                },
                {
                    "name": "component-2",
                    "containerImage": "quay.io/test/image2:v1",
                    "ocpVersion": ["v4.17"],
                    "ocpVersionMetadata": [
                        {
                            "version": "v4.17",
                            "updatedFromIndex": "registry.io/index:v4.17",
                            "targetIndex": "registry.io/target:v4.17-1234567890",
                        },
                    ],
                },
            ]
        }

        (data_dir / "data.json").write_text(json.dumps(data_file))
        (data_dir / "snapshot.json").write_text(json.dumps(snapshot_file))

        results_dir = data_dir / "results"
        results_dir.mkdir()

        return {
            "data_dir": str(data_dir),
            "data_file": data_file,
            "snapshot_file": snapshot_file,
        }

    def test_prepare_inputs_basic(self, setup_test_files, tmp_path):
        """Test basic prepare_inputs functionality."""
        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=setup_test_files["data_dir"],
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        config = prepare_inputs(args)

        assert config.build_timeout_seconds == 1800
        assert config.request_timeout_seconds == 1800
        assert config.internal_request_service_account == "test-sa"
        assert config.publishing_credentials == "test-creds"
        assert config.total_components == 2
        assert "v4.17" in config.ocp_versions
        assert "v4.18" in config.ocp_versions
        assert config.is_staged is False

    def test_prepare_inputs_creates_ocp_groups(self, setup_test_files, tmp_path):
        """Test that prepare_inputs creates OCP group files."""
        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=setup_test_files["data_dir"],
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        config = prepare_inputs(args)

        groups_dir = Path(config.groups_dir)
        assert groups_dir.exists()

        v417_file = groups_dir / "v4.17.json"
        assert v417_file.exists()
        v417_components = json.loads(v417_file.read_text())
        assert len(v417_components) == 2

        v418_file = groups_dir / "v4.18.json"
        assert v418_file.exists()
        v418_components = json.loads(v418_file.read_text())
        assert len(v418_components) == 1

    def test_prepare_inputs_missing_data_file(self, tmp_path):
        """Test that prepare_inputs raises TaskError when data file is missing."""
        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=str(tmp_path),
            data_path="nonexistent.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        with pytest.raises(TaskError) as exc_info:
            prepare_inputs(args)
        assert "No valid data file" in str(exc_info.value)

    def test_prepare_inputs_empty_components(self, tmp_path):
        """Test that prepare_inputs raises TaskError when snapshot has no components."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        data_file = {"fbc": {}}
        snapshot_file = {"components": []}

        (data_dir / "data.json").write_text(json.dumps(data_file))
        (data_dir / "snapshot.json").write_text(json.dumps(snapshot_file))

        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=str(data_dir),
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        with pytest.raises(TaskError) as exc_info:
            prepare_inputs(args)
        assert "components" in str(exc_info.value)

    def test_prepare_inputs_component_missing_ocp_version(self, tmp_path):
        """Test that prepare_inputs raises TaskError when a component has no ocpVersion."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        data_file = {"fbc": {}}
        snapshot_file = {
            "components": [
                {
                    "name": "component-without-ocp",
                    "containerImage": "quay.io/test/image:v1",
                },
            ]
        }

        (data_dir / "data.json").write_text(json.dumps(data_file))
        (data_dir / "snapshot.json").write_text(json.dumps(snapshot_file))

        results_dir = data_dir / "results"
        results_dir.mkdir()

        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=str(data_dir),
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        with pytest.raises(TaskError) as exc_info:
            prepare_inputs(args)
        assert "missing or empty ocpVersion" in str(exc_info.value)

    def test_prepare_inputs_component_empty_ocp_version(self, tmp_path):
        """Test that prepare_inputs raises TaskError when a component has empty ocpVersion list."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        data_file = {"fbc": {}}
        snapshot_file = {
            "components": [
                {
                    "name": "component-empty-ocp",
                    "containerImage": "quay.io/test/image:v1",
                    "ocpVersion": [],
                },
            ]
        }

        (data_dir / "data.json").write_text(json.dumps(data_file))
        (data_dir / "snapshot.json").write_text(json.dumps(snapshot_file))

        results_dir = data_dir / "results"
        results_dir.mkdir()

        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=str(data_dir),
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-123",
            task_run_uid="task-456",
            results_dir_path="results",
            task_git_url="https://github.com/repo",
            task_git_revision="main",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="test-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        with pytest.raises(TaskError) as exc_info:
            prepare_inputs(args)
        assert "missing or empty ocpVersion" in str(exc_info.value)


class TestCollectAndDeduplicate:
    """Tests for the collect_and_deduplicate function."""

    @pytest.fixture
    def setup_results(self, tmp_path):
        """Create test results files."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        results_file = data_dir / "results.json"
        results = {
            "components": [
                {
                    "fbc_fragment": "fragment1",
                    "target_index": "registry.io/target:v4.17",
                    "ocp_version": "v4.17",
                    "completion_time": "1234567890",
                },
                {
                    "fbc_fragment": "fragment2",
                    "target_index": "registry.io/target:v4.17",
                    "ocp_version": "v4.17",
                    "completion_time": "1234567891",
                },
                {
                    "fbc_fragment": "fragment3",
                    "target_index": "registry.io/target:v4.18",
                    "ocp_version": "v4.18",
                    "completion_time": "1234567892",
                },
            ]
        }
        results_file.write_text(json.dumps(results))

        snapshot_file = data_dir / "snapshot.json"
        snapshot = {"components": [{"name": "c1"}, {"name": "c2"}, {"name": "c3"}]}
        snapshot_file.write_text(json.dumps(snapshot))

        batch_result = {
            "exitCode": 0,
            "iibLog": "Build completed successfully",
            "indexImageDigests": "sha256:abc sha256:def",
        }
        # Filename includes OCP version to prevent collisions between groups
        batch_file = data_dir / "ir-task-456-v4.17-batch-1-result.json"
        batch_file.write_text(json.dumps(batch_result))

        config = Config(
            build_timeout_seconds=3600,
            request_timeout_seconds=3600,
            internal_request_service_account="test-sa",
            publishing_credentials="test-creds",
            iib_service_account_secret="test-secret",
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            build_tags=["tag1"],
            add_arches=["amd64"],
            ocp_versions=["v4.17", "v4.18"],
            total_components=3,
            max_batch_size=5,
            pipeline_timeout="1h5m0s",
            task_timeout="1h0m0s",
            groups_dir=str(data_dir / "ocp-groups"),
            results_file=str(results_file),
            is_staged=False,
        )

        args = argparse.Namespace(
            data_dir=str(data_dir),
            snapshot_path="snapshot.json",
        )

        return {
            "data_dir": str(data_dir),
            "config": config,
            "args": args,
        }

    def test_collect_and_deduplicate_removes_duplicates(self, setup_results):
        """Test that deduplication keeps only the last component per target."""
        collect_and_deduplicate(setup_results["args"], setup_results["config"])

        results = load_json_file(setup_results["config"].results_file)
        assert len(results["components"]) == 2

        v417_components = [
            c for c in results["components"]
            if c.get("target_index") == "registry.io/target:v4.17"
        ]
        assert len(v417_components) == 1
        assert v417_components[0]["fbc_fragment"] == "fragment2"

    def test_collect_and_deduplicate_no_duplicates(self, tmp_path):
        """Test that no deduplication occurs when there are no duplicates."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        results_file = data_dir / "results.json"
        results = {
            "components": [
                {
                    "fbc_fragment": "fragment1",
                    "target_index": "registry.io/target:v4.17",
                    "ocp_version": "v4.17",
                },
                {
                    "fbc_fragment": "fragment2",
                    "target_index": "registry.io/target:v4.18",
                    "ocp_version": "v4.18",
                },
            ]
        }
        results_file.write_text(json.dumps(results))

        snapshot_file = data_dir / "snapshot.json"
        snapshot = {"components": [{"name": "c1"}, {"name": "c2"}]}
        snapshot_file.write_text(json.dumps(snapshot))

        batch_result = {"exitCode": 0, "iibLog": "Success"}
        # Filename includes OCP version to prevent collisions between groups
        batch_file = data_dir / "ir-task-456-v4.17-batch-1-result.json"
        batch_file.write_text(json.dumps(batch_result))

        config = Config(
            build_timeout_seconds=3600,
            request_timeout_seconds=3600,
            internal_request_service_account="test-sa",
            publishing_credentials="test-creds",
            iib_service_account_secret="test-secret",
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            build_tags=["tag1"],
            add_arches=["amd64"],
            ocp_versions=["v4.17", "v4.18"],
            total_components=2,
            max_batch_size=5,
            pipeline_timeout="1h5m0s",
            task_timeout="1h0m0s",
            groups_dir=str(data_dir / "ocp-groups"),
            results_file=str(results_file),
            is_staged=False,
        )

        args = argparse.Namespace(
            data_dir=str(data_dir),
            snapshot_path="snapshot.json",
        )

        collect_and_deduplicate(args, config)

        final_results = load_json_file(str(results_file))
        assert len(final_results["components"]) == 2

    def test_collect_and_deduplicate_staged_release(self, tmp_path):
        """Test deduplication for staged releases (uses ocp_version as key)."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        results_file = data_dir / "results.json"
        results = {
            "components": [
                {
                    "fbc_fragment": "fragment1",
                    "target_index": "",
                    "ocp_version": "v4.17",
                },
                {
                    "fbc_fragment": "fragment2",
                    "target_index": "",
                    "ocp_version": "v4.17",
                },
            ]
        }
        results_file.write_text(json.dumps(results))

        snapshot_file = data_dir / "snapshot.json"
        snapshot = {"components": [{"name": "c1"}, {"name": "c2"}]}
        snapshot_file.write_text(json.dumps(snapshot))

        batch_result = {"exitCode": 0, "iibLog": "Success"}
        # Filename includes OCP version to prevent collisions between groups
        batch_file = data_dir / "ir-task-456-v4.17-batch-1-result.json"
        batch_file.write_text(json.dumps(batch_result))

        config = Config(
            build_timeout_seconds=3600,
            request_timeout_seconds=3600,
            internal_request_service_account="test-sa",
            publishing_credentials="test-creds",
            iib_service_account_secret="test-secret",
            must_publish_index_image="false",
            must_overwrite_from_index_image="false",
            build_tags=[],
            add_arches=["amd64"],
            ocp_versions=["v4.17"],
            total_components=2,
            max_batch_size=5,
            pipeline_timeout="1h5m0s",
            task_timeout="1h0m0s",
            groups_dir=str(data_dir / "ocp-groups"),
            results_file=str(results_file),
            is_staged=True,
        )

        args = argparse.Namespace(
            data_dir=str(data_dir),
            snapshot_path="snapshot.json",
        )

        collect_and_deduplicate(args, config)

        final_results = load_json_file(str(results_file))
        assert len(final_results["components"]) == 1
        assert final_results["components"][0]["fbc_fragment"] == "fragment2"


class TestResultWriter:
    """Tests for the ResultWriter class."""

    def test_result_writer_success(self, tmp_path):
        """Test that ResultWriter writes Success status."""
        result_file = tmp_path / "result"

        writer = ResultWriter(str(result_file))
        writer.set_success()
        writer._write_result()

        assert result_file.read_text() == "Success"

    def test_result_writer_failure(self, tmp_path):
        """Test that ResultWriter writes Failure status."""
        result_file = tmp_path / "result"

        writer = ResultWriter(str(result_file))
        writer.set_failure("Something went wrong")
        writer._write_result()

        assert result_file.read_text() == "Failure"
        assert writer.error_message == "Something went wrong"

    def test_result_writer_default_is_failure(self, tmp_path):
        """Test that ResultWriter defaults to Failure status."""
        result_file = tmp_path / "result"

        writer = ResultWriter(str(result_file))
        writer._write_result()

        assert result_file.read_text() == "Failure"


class TestTaskError:
    """Tests for the TaskError exception."""

    def test_task_error_message(self):
        """Test that TaskError carries a message."""
        error = TaskError("Test error message")
        assert str(error) == "Test error message"


class TestConfig:
    """Tests for the Config dataclass."""

    def test_config_creation(self):
        """Test creating a Config object."""
        config = Config(
            build_timeout_seconds=3600,
            request_timeout_seconds=3600,
            internal_request_service_account="test-sa",
            publishing_credentials="test-creds",
            iib_service_account_secret="test-secret",
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            build_tags=["tag1", "tag2"],
            add_arches=["amd64"],
            ocp_versions=["v4.17", "v4.18"],
            total_components=5,
            max_batch_size=3,
            pipeline_timeout="1h5m0s",
            task_timeout="1h0m0s",
            groups_dir="/tmp/groups",
            results_file="/tmp/results.json",
            is_staged=False,
        )

        assert config.build_timeout_seconds == 3600
        assert config.total_components == 5
        assert len(config.ocp_versions) == 2
        assert config.is_staged is False


class TestBatchCalculation:
    """Tests for batch calculation logic."""

    def test_batch_count_exact_division(self):
        """Test batch count when components divide evenly."""
        total = 10
        batch_size = 5
        expected_batches = 2

        num_batches = (total + batch_size - 1) // batch_size
        assert num_batches == expected_batches

    def test_batch_count_with_remainder(self):
        """Test batch count when there's a remainder."""
        total = 7
        batch_size = 3
        expected_batches = 3

        num_batches = (total + batch_size - 1) // batch_size
        assert num_batches == expected_batches

    def test_batch_count_single_batch(self):
        """Test batch count when all components fit in one batch."""
        total = 3
        batch_size = 5
        expected_batches = 1

        num_batches = (total + batch_size - 1) // batch_size
        assert num_batches == expected_batches


class TestIntegration:
    """Integration tests for the full workflow."""

    @pytest.fixture
    def full_setup(self, tmp_path):
        """Create a complete test environment."""
        data_dir = tmp_path / "data"
        data_dir.mkdir()

        data_file = {
            "fbc": {
                "buildTimeoutSeconds": 1800,
                "requestTimeoutSeconds": 1800,
                "internalRequestServiceAccount": "test-sa",
                "publishingCredentials": "test-creds",
                "buildTags": ["release-tag"],
                "addArches": ["amd64", "arm64"],
                "stagedIndex": False,
            }
        }

        snapshot_file = {
            "components": [
                {
                    "name": "operator-bundle",
                    "containerImage": "quay.io/test/bundle:v1.0.0",
                    "ocpVersion": ["v4.17"],
                    "ocpVersionMetadata": [
                        {
                            "version": "v4.17",
                            "updatedFromIndex": "registry.io/redhat/index:v4.17",
                            "targetIndex": "registry.io/redhat/target:v4.17-release",
                        },
                    ],
                },
            ]
        }

        (data_dir / "data.json").write_text(json.dumps(data_file))
        (data_dir / "snapshot.json").write_text(json.dumps(snapshot_file))

        results_dir = data_dir / "results"
        results_dir.mkdir()

        return {
            "data_dir": str(data_dir),
            "results_dir": str(results_dir),
        }

    def test_prepare_inputs_creates_valid_config(self, full_setup, tmp_path):
        """Test that prepare_inputs creates a valid configuration."""
        results_file = tmp_path / "request_results"
        internal_results_file = tmp_path / "internal_results"

        args = argparse.Namespace(
            data_dir=full_setup["data_dir"],
            data_path="data.json",
            snapshot_path="snapshot.json",
            pipeline_run_uid="pipeline-abc123",
            task_run_uid="task-def456",
            results_dir_path="results",
            task_git_url="https://github.com/konflux-ci/release-service-catalog",
            task_git_revision="development",
            max_batch_size=5,
            must_publish_index_image="true",
            must_overwrite_from_index_image="false",
            iib_service_account_secret="iib-secret",
            request_results_file_path=str(results_file),
            internal_request_results_file_path=str(internal_results_file),
        )

        config = prepare_inputs(args)

        assert config.total_components == 1
        assert config.ocp_versions == ["v4.17"]
        assert config.must_publish_index_image == "true"
        assert config.build_timeout_seconds == 1800

        groups_dir = Path(config.groups_dir)
        assert (groups_dir / "v4.17.json").exists()

        v417_components = load_json_file(str(groups_dir / "v4.17.json"))
        assert len(v417_components) == 1
        assert v417_components[0]["containerImage"] == "quay.io/test/bundle:v1.0.0"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
