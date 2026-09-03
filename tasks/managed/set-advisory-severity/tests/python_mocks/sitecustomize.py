"""Mock InternalRequest Kubernetes API calls for Tekton tests.

Loaded automatically by the Python interpreter from PYTHONPATH before the task
script runs.  The merged internal_request helper talks to the API via the
Kubernetes Python client, so a kubectl mock on PATH is never consulted.
"""

from __future__ import annotations

from typing import Any

from kubernetes import client as k8s_client

_SUCCESS_IR: dict[str, Any] = {
    "apiVersion": "appstudio.redhat.com/v1alpha1",
    "kind": "InternalRequest",
    "metadata": {"name": "success-ir", "namespace": "default"},
    "status": {
        "conditions": [{"reason": "Succeeded", "status": "True", "type": "Succeeded"}],
        "results": {"result": "Success", "severity": "IMPORTANT"},
        "pipelineRun": "test-run",
    },
}


def _list_namespaced_custom_object(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
    """Return no prior InternalRequests so cleanup is a no-op."""
    return {"items": []}


def _create_namespaced_custom_object(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
    """Pretend the InternalRequest was created."""
    return {"metadata": {"name": "success-ir"}}


def _get_namespaced_custom_object(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
    """Return a completed InternalRequest with severity IMPORTANT."""
    return _SUCCESS_IR


def _delete_namespaced_custom_object(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
    """Pretend the InternalRequest was deleted."""
    return {}


k8s_client.CustomObjectsApi.list_namespaced_custom_object = _list_namespaced_custom_object
k8s_client.CustomObjectsApi.create_namespaced_custom_object = (
    _create_namespaced_custom_object
)
k8s_client.CustomObjectsApi.get_namespaced_custom_object = _get_namespaced_custom_object
k8s_client.CustomObjectsApi.delete_namespaced_custom_object = (
    _delete_namespaced_custom_object
)
