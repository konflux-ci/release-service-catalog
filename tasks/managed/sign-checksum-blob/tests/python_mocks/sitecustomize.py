"""Mock InternalRequest Kubernetes API calls for the checksum-signing test."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from kubernetes import client as k8s_client

_IR_NAME = "generic-signing-mock"
_IR: dict[str, Any] = {
    "apiVersion": "appstudio.redhat.com/v1alpha1",
    "kind": "InternalRequest",
    "metadata": {"name": _IR_NAME, "namespace": "default"},
    "status": {
        "conditions": [{"reason": "Succeeded", "status": "True", "type": "Succeeded"}],
        "results": {},
        "pipelineRun": "pr-mock",
    },
}


def _list_namespaced_custom_object(
    self: Any, *args: Any, **kwargs: Any
) -> dict[str, Any]:
    """Return no prior InternalRequests so cleanup is a no-op."""
    return {"items": []}


def _create_namespaced_custom_object(
    self: Any, *args: Any, **kwargs: Any
) -> dict[str, Any]:
    """Record the request and return its generated name."""
    data_dir = Path(os.environ["DATA_DIR"])
    data_dir.joinpath("mock_kubectl_create.json").write_text(
        json.dumps(kwargs["body"], separators=(",", ":")), encoding="utf-8"
    )
    return {"metadata": {"name": _IR_NAME}}


def _get_namespaced_custom_object(
    self: Any, *args: Any, **kwargs: Any
) -> dict[str, Any]:
    """Return a completed request referencing the prepared output artifact."""
    response = {**_IR, "status": {**_IR["status"]}}
    response["status"]["results"] = {
        "sourceDataArtifact": Path(os.environ["DATA_DIR"])
        .joinpath("mock-signed-output-artifact.txt")
        .read_text(encoding="utf-8")
        .strip()
    }
    return response


def _delete_namespaced_custom_object(
    self: Any, *args: Any, **kwargs: Any
) -> dict[str, Any]:
    """Pretend the InternalRequest was deleted."""
    return {}


k8s_client.CustomObjectsApi.list_namespaced_custom_object = (
    _list_namespaced_custom_object
)
k8s_client.CustomObjectsApi.create_namespaced_custom_object = (
    _create_namespaced_custom_object
)
k8s_client.CustomObjectsApi.get_namespaced_custom_object = _get_namespaced_custom_object
k8s_client.CustomObjectsApi.delete_namespaced_custom_object = (
    _delete_namespaced_custom_object
)
