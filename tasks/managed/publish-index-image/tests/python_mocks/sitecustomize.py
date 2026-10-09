"""Sitecustomize for publish-index-image tests - mocks internal_request create/fetch_results.

Python loads sitecustomize.py automatically on startup. Import real modules first,
then inject mocks into sys.modules.
"""

import base64
import gzip
import json
import sys
import threading
import time
from pathlib import Path
from types import ModuleType
from typing import Any

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config

# Import real modules (sitecustomize loads before user code, so this is safe)
import release_service_utils.helpers.internal_request as _real_internal_request

# Create mock internal_request module

_IR_GROUP = "appstudio.redhat.com"
_IR_VERSION = "v1alpha1"
_IR_PLURAL = "internalrequests"
_NAMESPACE_FILE = Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
_MOCK_RESULTS: dict[str, dict[str, Any]] = {}


class InternalRequestWaitError(RuntimeError):
    """Raised when waiting for InternalRequests fails or times out."""

    def __init__(self, message: str, exit_code: int) -> None:
        super().__init__(message)
        self.exit_code = exit_code


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


_test_should_fail = False  # Global flag set by create_internal_request


def _create_mock_results():
    build_info = {
        "updated": "2024-03-06T16:39:11.314092Z",
        "index_image": "redhat.com/rh-stage/iib:01",
        "internal_index_image_copy_resolved": "redhat.com/rh-stage/iib@sha256:abcdefghijk",
    }
    json_build_info = base64.b64encode(
        gzip.compress(json.dumps(build_info).encode("utf-8"))
    ).decode("ascii")

    # Use global flag set by test
    exit_code = "1" if _test_should_fail else "0"

    return {
        "jsonBuildInfo": json_build_info,
        "indexImageDigests": "quay.io/a quay.io/b",
        "iibLog": "Dummy IIB Log",
        "exitCode": exit_code,
    }


def _patch_status_async(ir_name, results, delay=1.0):
    def _patch():
        print(f"MOCK: patch thread started for {ir_name}, delay={delay}s", flush=True)
        time.sleep(delay)
        try:
            k8s_api = _default_k8s_api()
            namespace = _get_namespace()
            print(f"MOCK: patching in namespace={namespace}", flush=True)

            # Determine success/failure based on exitCode
            exit_code = results.get("exitCode", "0")
            succeeded = exit_code == "0"
            print(f"MOCK: patching {ir_name} with exitCode={exit_code}, succeeded={succeeded}", flush=True)

            patch = {
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
                    # Use status subresource API
                    k8s_api.patch_namespaced_custom_object_status(
                        group=_IR_GROUP,
                        version=_IR_VERSION,
                        namespace=namespace,
                        plural=_IR_PLURAL,
                        name=ir_name,
                        body=patch,
                    )
                    # Verify patch by reading back
                    ir = k8s_api.get_namespaced_custom_object(
                        group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, name=ir_name
                    )
                    status_keys = list(ir.get("status", {}).keys())
                    print(f"MOCK: successfully patched {ir_name}, status keys after patch: {status_keys}", flush=True)
                    break
                except Exception as e:
                    if attempt == 4:
                        print(f"ERROR: Failed to patch {ir_name}: {e}", flush=True)
                    time.sleep(1)
        except Exception as e:
            print(f"ERROR in patch thread for {ir_name}: {e}", flush=True)

    threading.Thread(target=_patch, daemon=True).start()


def create_internal_request(payload, *, k8s_api=None):
    """Mock create_internal_request - creates IR from payload and patches status."""
    global _test_should_fail

    # Check for failure marker only once per test run
    if not hasattr(create_internal_request, '_checked_marker'):
        failure_marker = Path("/var/workdir/release/.test-failure-marker")
        _test_should_fail = failure_marker.exists()
        print(f"MOCK: marker check: exists={_test_should_fail}", flush=True)
        create_internal_request._checked_marker = True

    print(f"MOCK: create_internal_request() called", flush=True)
    if k8s_api is None:
        k8s_api = _default_k8s_api()

    namespace = _get_namespace()
    resource = k8s_api.create_namespaced_custom_object(
        group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, body=payload
    )
    ir_name = resource["metadata"]["name"]

    mock_results = _create_mock_results()
    _MOCK_RESULTS[ir_name] = mock_results
    _patch_status_async(ir_name, mock_results, delay=0.1)  # Fast patch for tests

    return ir_name


def wait_for_completion(name, *, timeout=3600, k8s_api=None):
    """Mock wait_for_completion - polls IR status and raises on failure."""
    print(f"MOCK: wait_for_completion() called for {name}", flush=True)
    if k8s_api is None:
        k8s_api = _default_k8s_api()

    namespace = _get_namespace()
    print(f"MOCK: wait using namespace={namespace}", flush=True)
    max_attempts = int(timeout / 0.5)

    for attempt in range(max_attempts):
        time.sleep(0.5)

        ir = k8s_api.get_namespaced_custom_object(
            group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, name=name
        )

        status = ir.get("status", {})
        conditions = status.get("conditions", [])
        if attempt < 5 or attempt % 10 == 0:  # Debug first 5 attempts, then every 10th
            print(f"MOCK: wait attempt {attempt}, status keys: {list(status.keys())}, conditions: {conditions}", flush=True)

        for condition in conditions:
            if condition.get("type") == "Succeeded":
                if condition.get("status") == "False":
                    mock_results = _MOCK_RESULTS.get(name, {})
                    exit_code = int(mock_results.get("exitCode", "1"))
                    print(f"MOCK: IR {name} failed, raising error", flush=True)
                    raise InternalRequestWaitError(
                        f"InternalRequest {name} failed: {condition.get('message', '')}",
                        exit_code
                    )
                # Success
                print(f"MOCK: IR {name} succeeded", flush=True)
                return

    # Timeout
    print(f"MOCK: IR {name} timed out", flush=True)
    raise InternalRequestWaitError(f"Timeout waiting for InternalRequest {name}", 1)


def fetch_results(internal_request_name, *, k8s_api=None):
    """Mock fetch_results - returns stored mock results after checking status."""
    if k8s_api is None:
        k8s_api = _default_k8s_api()
    namespace = _get_namespace()

    # Poll for status to be set
    max_attempts = 10
    resource = None
    for attempt in range(max_attempts):
        resource = k8s_api.get_namespaced_custom_object(
            group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, name=internal_request_name
        )
        conditions = resource.get("status", {}).get("conditions", [])
        if conditions:
            break
        time.sleep(0.5)

    # Check if IR failed
    if resource:
        conditions = resource.get("status", {}).get("conditions", [])
        for condition in conditions:
            if condition.get("type") == "Succeeded" and condition.get("status") == "False":
                results = resource.get("status", {}).get("results", {})
                exit_code = int(results.get("exitCode", "1"))
                raise InternalRequestWaitError(
                    f"InternalRequest {internal_request_name} failed: {condition.get('message', '')}",
                    exit_code
                )

    # Return results from cache or resource
    if internal_request_name in _MOCK_RESULTS:
        return _MOCK_RESULTS[internal_request_name]

    results = resource.get("status", {}).get("results") if resource else {}
    return results if isinstance(results, dict) else {}


# Store all real functions/classes from the already-loaded internal_request module
_real_exports = {name: getattr(_real_internal_request, name) for name in dir(_real_internal_request) if not name.startswith('_')}

# Create mock internal_request module that wraps the real one
class _MockInternalRequestModule(ModuleType):
    """Wrapper for internal_request that overrides key functions."""

    def __getattr__(self, name):
        # Override these specific functions
        if name == "create_internal_request":
            return create_internal_request
        elif name == "wait_for_completion":
            return wait_for_completion
        elif name == "fetch_results":
            return fetch_results
        elif name == "InternalRequestWaitError":
            return InternalRequestWaitError
        # Delegate everything else to real module
        if name in _real_exports:
            return _real_exports[name]
        raise AttributeError(f"module 'internal_request' has no attribute '{name}'")


_internal_request_mod = _MockInternalRequestModule("internal_request")

# Inject mock into sys.modules to override the real internal_request
sys.modules["release_service_utils.helpers.internal_request"] = _internal_request_mod

# Debug: confirm mock loaded
print("MOCK: sitecustomize loaded, internal_request mocked", flush=True)
