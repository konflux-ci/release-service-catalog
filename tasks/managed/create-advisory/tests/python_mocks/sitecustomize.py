"""Sitecustomize for create-advisory tests - mocks internal_request create/fetch_results.

Python loads sitecustomize.py automatically on startup. Import real modules first,
then inject mocks into sys.modules.
"""

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

# Save references to specific real functions we need
_real_create_internal_request = _real_internal_request.create_internal_request
_real_build_payload = _real_internal_request.build_payload
_real_InternalRequestWaitError = _real_internal_request.InternalRequestWaitError

# Create mock internal_request module

_IR_GROUP = "appstudio.redhat.com"
_IR_VERSION = "v1alpha1"
_IR_PLURAL = "internalrequests"
_NAMESPACE_FILE = Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
_MOCK_RESULTS: dict[str, dict[str, Any]] = {}


# Use the real error class
InternalRequestWaitError = _real_InternalRequestWaitError


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
    """Create mock results for create-advisory InternalRequest."""
    return {
        "result": "Success",
        "advisory_url": "https://access.redhat.com/errata/RHBA-2025:1111",
        "advisory_internal_url": "https://errata.devel.redhat.com/advisory/123456",
        "internalRequestPipelineRunName": "mock-pipeline-run",
        "internalRequestTaskRunName": "mock-task-run",
    }


def _patch_status_async(ir_name, results, delay=0.01):
    """Asynchronously patch InternalRequest status after delay."""

    def _patch():
        print(f"MOCK: patch thread started for {ir_name}, delay={delay}s", flush=True)
        time.sleep(delay)
        try:
            k8s_api = _default_k8s_api()
            namespace = _get_namespace()
            print(f"MOCK: patching in namespace={namespace}", flush=True)

            # Advisory creation always succeeds in test
            succeeded = results.get("result") == "Success"
            print(
                f"MOCK: patching {ir_name} with result={results.get('result')}, succeeded={succeeded}",
                flush=True,
            )

            patch = {
                "status": {
                    "results": results,
                    "conditions": [
                        {
                            "type": "Succeeded",
                            "status": "True" if succeeded else "False",
                            "reason": "Succeeded" if succeeded else "Failed",
                            "message": "" if succeeded else "InternalRequest failed",
                            "lastTransitionTime": time.strftime(
                                "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
                            ),
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
                        group=_IR_GROUP,
                        version=_IR_VERSION,
                        namespace=namespace,
                        plural=_IR_PLURAL,
                        name=ir_name,
                    )
                    status_keys = list(ir.get("status", {}).keys())
                    print(
                        f"MOCK: successfully patched {ir_name}, status keys after patch: {status_keys}",
                        flush=True,
                    )
                    break
                except Exception as e:
                    if attempt == 4:
                        print(f"ERROR: Failed to patch {ir_name}: {e}", flush=True)
                    time.sleep(1)
        except Exception as e:
            print(f"ERROR in patch thread for {ir_name}: {e}", flush=True)

    threading.Thread(target=_patch, daemon=True).start()


def create_internal_request(payload, *, k8s_api=None):
    """Mock create_internal_request - creates IR via real function and patches status."""
    print("MOCK: create_internal_request() called", flush=True)
    if k8s_api is None:
        k8s_api = _default_k8s_api()

    # Use the real create_internal_request to create the IR with proper payload
    ir_name = _real_create_internal_request(payload, k8s_api=k8s_api)

    print(f"MOCK: created real InternalRequest {ir_name}", flush=True)

    # Mock the async status update
    mock_results = _create_mock_results()
    _MOCK_RESULTS[ir_name] = mock_results
    _patch_status_async(ir_name, mock_results, delay=0.01)

    return ir_name


def fetch_results(ir_name, *, k8s_api=None, timeout_seconds=300, poll_seconds=3):
    """Mock fetch_results - waits for async patch to complete, then returns cached results."""
    print(f"MOCK: fetch_results({ir_name}) called", flush=True)

    if k8s_api is None:
        k8s_api = _default_k8s_api()
    namespace = _get_namespace()

    # Wait for status to be patched by the async thread
    max_attempts = int(timeout_seconds / 0.1)
    for attempt in range(max_attempts):
        try:
            ir = k8s_api.get_namespaced_custom_object(
                group=_IR_GROUP,
                version=_IR_VERSION,
                namespace=namespace,
                plural=_IR_PLURAL,
                name=ir_name,
            )
            status = ir.get("status", {})
            results = status.get("results", {})
            if results:
                print(f"MOCK: IR status patched, returning results for {ir_name}", flush=True)
                return results
        except Exception as e:
            print(f"MOCK: error fetching IR {ir_name}: {e}", flush=True)
        time.sleep(0.1)

    # Return cached results as fallback
    if ir_name in _MOCK_RESULTS:
        print(f"MOCK: timeout waiting for patch, returning cached results for {ir_name}", flush=True)
        return _MOCK_RESULTS[ir_name]

    # Final fallback to empty dict
    print(f"MOCK: no cached results for {ir_name}, returning empty dict", flush=True)
    return {}


def create(
    pipeline,
    *,
    params=None,
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
    """Mock create - builds payload and calls our mock create_internal_request directly."""
    print(f"MOCK: create() called with pipeline={pipeline}, sync={sync}", flush=True)

    if k8s_api is None:
        k8s_api = _default_k8s_api()

    # Extract git URL/revision from params (passed by create-advisory task)
    params_dict = params or {}
    git_url = params_dict.get("taskGitUrl", "")
    git_revision = params_dict.get("taskGitRevision", "")

    # Build payload using real build_payload
    payload = _real_build_payload(
        pipeline=pipeline,
        params=params_dict,
        labels=labels or {},
        pipeline_git_url=git_url,
        pipeline_git_revision=git_revision,
        pipeline_timeout=pipeline_timeout,
        task_timeout=task_timeout,
        finally_timeout=finally_timeout,
        service_account=service_account,
    )

    # Call OUR mock create_internal_request, not the real one
    ir_name = create_internal_request(payload, k8s_api=k8s_api)

    print(f"MOCK: created IR {ir_name} for pipeline {pipeline}", flush=True)

    # If sync, fetch results ourselves
    if sync:
        print(f"MOCK: sync=True, fetching results", flush=True)
        results = fetch_results(ir_name, k8s_api=k8s_api, timeout_seconds=timeout)
        # Check if succeeded
        if results.get("result") != "Success":
            raise InternalRequestWaitError(f"InternalRequest {ir_name} failed", 1)

    return ir_name


# Create mock internal_request module that wraps the real one
_mock_mod = ModuleType("release_service_utils.helpers.internal_request")

# Copy all attributes from real module
for name in dir(_real_internal_request):
    if not name.startswith("_"):
        setattr(_mock_mod, name, getattr(_real_internal_request, name))

# Override with our mocks
_mock_mod.create = create
_mock_mod.create_internal_request = create_internal_request
_mock_mod.fetch_results = fetch_results
_mock_mod.InternalRequestWaitError = InternalRequestWaitError

# CRITICAL: Also patch the real module object so internal calls use our mocks
_real_internal_request.create_internal_request = create_internal_request
_real_internal_request.fetch_results = fetch_results

# Inject mock into sys.modules to override the real internal_request
sys.modules["release_service_utils.helpers.internal_request"] = _mock_mod

# ALSO set it as an attribute of the helpers package so "from helpers import internal_request" works
import release_service_utils.helpers as helpers_pkg
helpers_pkg.internal_request = _mock_mod

# Debug: confirm mock loaded
print("MOCK: sitecustomize loaded, internal_request mocked", flush=True)
print(f"MOCK: create_internal_request function is: {_mock_mod.create_internal_request}", flush=True)
