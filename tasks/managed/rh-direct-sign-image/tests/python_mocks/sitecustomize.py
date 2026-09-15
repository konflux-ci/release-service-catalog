"""Pre-register a mock release_service_utils.helpers.internal_request module.

Python imports sitecustomize.py from sys.path during startup (before any user
code). This mock replaces the real internal_request package so the task script
never loads the kubernetes client or hits the cluster API.

The mock create() builds the same IR manifest payload that build_payload()
would produce and writes it to $DATA_DIR/mock_internal_request.txt for the
check-result step to verify.
"""

import json
import os
import sys
import types

_mod = types.ModuleType("release_service_utils.helpers.internal_request")
_mod.__package__ = "release_service_utils.helpers"


class InternalRequestWaitError(RuntimeError):
    """Mock version of the real exception for tests that catch it."""

    def __init__(self, message: str, exit_code: int) -> None:
        super().__init__(message)
        self.exit_code = exit_code


_counter = 0


def create(
    pipeline,
    *,
    params,
    labels=None,
    sync=True,
    timeout=3600,
    service_account=None,
    pipeline_timeout="1h0m0s",
    task_timeout="0h55m0s",
    finally_timeout="0h5m0s",
    cleanup=True,
    k8s_api=None,
):
    global _counter
    _counter += 1

    merged_labels = dict(labels or {})
    merged_params = dict(params)
    pipeline_git_url = merged_params.get("taskGitUrl", "")
    pipeline_git_revision = merged_params.get("taskGitRevision", "")

    payload = {
        "apiVersion": "appstudio.redhat.com/v1alpha1",
        "kind": "InternalRequest",
        "metadata": {
            "generateName": f"{pipeline}-",
            "labels": merged_labels,
        },
        "spec": {
            "pipeline": {
                "pipelineRef": {
                    "resolver": "git",
                    "params": [
                        {"name": "url", "value": pipeline_git_url},
                        {"name": "revision", "value": pipeline_git_revision},
                        {
                            "name": "pathInRepo",
                            "value": f"pipelines/internal/{pipeline}/{pipeline}.yaml",
                        },
                    ],
                },
            },
            "params": merged_params,
            "timeouts": {
                "pipeline": pipeline_timeout,
                "tasks": task_timeout,
                "finally": finally_timeout,
            },
        },
    }
    if service_account:
        payload["spec"]["serviceAccount"] = service_account

    data_dir = os.environ.get("DATA_DIR", "/tmp")
    mock_file = os.path.join(data_dir, "mock_internal_request.txt")
    with open(mock_file, "a") as fh:
        fh.write(json.dumps(payload))

    return f"mock-ir-{_counter}"


_mod.InternalRequestWaitError = InternalRequestWaitError
_mod.create = create

sys.modules["release_service_utils.helpers.internal_request"] = _mod
