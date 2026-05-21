"""Mock InternalRequest results for the publish-index-image task test.

The task creates the InternalRequest through the Kubernetes Python client, so
the test keeps that operation real to allow the check step to inspect the CR.
Only result retrieval is mocked because no InternalRequest controller runs in
the test cluster to populate ``status.results``.
"""

from __future__ import annotations

import base64
import gzip
import json
import threading
import time
from pathlib import Path
from unittest.mock import patch

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config
from release_service_utils.helpers import internal_request

_IR_GROUP = "appstudio.redhat.com"
_IR_VERSION = "v1alpha1"
_IR_PLURAL = "internalrequests"
_NAMESPACE_FILE = Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace")


def _default_k8s_api():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
    return k8s_client.CustomObjectsApi()


def _get_namespace():
    try:
        return _NAMESPACE_FILE.read_text().strip()
    except FileNotFoundError:
        _, context = k8s_config.list_kube_config_contexts()
        return context.get("context", {}).get("namespace", "default")


def _create_mock_results():
    """Build mock InternalRequest results for publish-index-image."""
    failure_marker = Path("/var/workdir/release/.test-failure-marker")
    exit_code = "1" if failure_marker.exists() else "0"

    build_info = {
        "updated": "2024-03-06T16:39:11.314092Z",
        "index_image": "redhat.com/rh-stage/iib:01",
        "internal_index_image_copy_resolved": "redhat.com/rh-stage/iib@sha256:abcdefghijk",
    }
    json_build_info = base64.b64encode(
        gzip.compress(json.dumps(build_info).encode("utf-8"))
    ).decode("ascii")

    return {
        "jsonBuildInfo": json_build_info,
        "indexImageDigests": "quay.io/a quay.io/b",
        "iibLog": "Dummy IIB Log",
        "exitCode": exit_code,
    }


def _patch_status_async(ir_name: str, results: dict, delay: float = 0.1):
    """Asynchronously patch InternalRequest status with results."""
    def _patch():
        time.sleep(delay)
        try:
            k8s_api = _default_k8s_api()
            namespace = _get_namespace()

            exit_code = results.get("exitCode", "0")
            succeeded = exit_code == "0"

            patch_body = {
                "status": {
                    "results": results,
                    "conditions": [
                        {
                            "type": "Succeeded",
                            "status": "True" if succeeded else "False",
                            "reason": "Succeeded" if succeeded else "Failed",
                            "message": "" if succeeded else "InternalRequest failed",
                            "lastTransitionTime": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        }
                    ],
                }
            }

            for attempt in range(5):
                try:
                    k8s_api.patch_namespaced_custom_object_status(
                        group=_IR_GROUP,
                        version=_IR_VERSION,
                        namespace=namespace,
                        plural=_IR_PLURAL,
                        name=ir_name,
                        body=patch_body,
                    )
                    break
                except Exception as e:
                    if attempt == 4:
                        print(f"ERROR: Failed to patch {ir_name}: {e}", flush=True)
                    time.sleep(1)
        except Exception as e:
            print(f"ERROR in patch thread for {ir_name}: {e}", flush=True)

    threading.Thread(target=_patch, daemon=True).start()


def _mock_create_internal_request(payload, *, k8s_api=None):
    """Create InternalRequest via real k8s client, then async-patch status."""
    if k8s_api is None:
        k8s_api = _default_k8s_api()

    namespace = _get_namespace()
    resource = k8s_api.create_namespaced_custom_object(
        group=_IR_GROUP,
        version=_IR_VERSION,
        namespace=namespace,
        plural=_IR_PLURAL,
        body=payload,
    )
    ir_name = resource["metadata"]["name"]

    mock_results = _create_mock_results()
    _patch_status_async(ir_name, mock_results)

    return ir_name


def _mock_wait_for_completion(name, *, timeout=3600, k8s_api=None):
    """Poll IR status and raise on failure (matches real wait_for_completion behavior)."""
    if k8s_api is None:
        k8s_api = _default_k8s_api()
    namespace = _get_namespace()

    max_attempts = int(timeout / 0.5)
    for _ in range(max_attempts):
        time.sleep(0.5)
        resource = k8s_api.get_namespaced_custom_object(
            group=_IR_GROUP,
            version=_IR_VERSION,
            namespace=namespace,
            plural=_IR_PLURAL,
            name=name,
        )
        conditions = resource.get("status", {}).get("conditions", [])
        for condition in conditions:
            if condition.get("type") == "Succeeded":
                if condition.get("status") == "False":
                    # Failure: raise error with exitCode from results
                    results = resource.get("status", {}).get("results", {})
                    exit_code = int(results.get("exitCode", "1"))
                    # Import the real exception class from the module
                    from release_service_utils.helpers.internal_request import InternalRequestWaitError
                    raise InternalRequestWaitError(
                        f"InternalRequest {name} failed: {condition.get('message', '')}",
                        exit_code
                    )
                # Success
                return

    # Timeout: raise error
    from release_service_utils.helpers.internal_request import InternalRequestWaitError
    raise InternalRequestWaitError(f"Timeout waiting for InternalRequest {name}", 1)


def _mock_fetch_results(internal_request_name, *, k8s_api=None):
    """Return mocked InternalRequest results after status is patched."""
    if k8s_api is None:
        k8s_api = _default_k8s_api()
    namespace = _get_namespace()

    # Poll for status.results to appear (async patch takes ~100ms)
    for _ in range(10):
        resource = k8s_api.get_namespaced_custom_object(
            group=_IR_GROUP,
            version=_IR_VERSION,
            namespace=namespace,
            plural=_IR_PLURAL,
            name=internal_request_name,
        )
        results = resource.get("status", {}).get("results")
        if results:
            return results if isinstance(results, dict) else {}
        time.sleep(0.5)

    return {}


patch.object(
    internal_request,
    "create_internal_request",
    autospec=True,
    side_effect=_mock_create_internal_request,
).start()

patch.object(
    internal_request,
    "wait_for_completion",
    autospec=True,
    side_effect=_mock_wait_for_completion,
).start()

patch.object(
    internal_request,
    "fetch_results",
    autospec=True,
    side_effect=_mock_fetch_results,
).start()
