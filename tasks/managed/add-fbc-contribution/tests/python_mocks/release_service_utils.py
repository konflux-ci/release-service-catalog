"""Mock release_service_utils for tests - proxies to real package but mocks internal_request."""

import base64
import gzip
import importlib.util
import json
import sys
import threading
import time
from pathlib import Path
from types import ModuleType
from typing import Any

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config

# Find and load real release_service_utils from site-packages, bypassing PYTHONPATH
_real_rsu = None
for path_entry in sys.path:
    if "site-packages" in path_entry or "dist-packages" in path_entry:
        rsu_path = Path(path_entry) / "release_service_utils"
        if rsu_path.is_dir() and (rsu_path / "__init__.py").exists():
            spec = importlib.util.spec_from_file_location(
                "_real_release_service_utils",
                rsu_path / "__init__.py",
                submodule_search_locations=[str(rsu_path)]
            )
            if spec and spec.loader:
                _real_rsu = importlib.util.module_from_spec(spec)
                sys.modules["_real_release_service_utils"] = _real_rsu
                spec.loader.exec_module(_real_rsu)
                break

if _real_rsu is None:
    raise RuntimeError("Could not find real release_service_utils package")

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


def _create_mock_results():
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
        "exitCode": "0",
    }


def _patch_status_async(ir_name, results, delay=1.0):
    def _patch():
        time.sleep(delay)
        try:
            k8s_api = _default_k8s_api()
            namespace = _get_namespace()
            patch = {
                "status": {
                    "results": results,
                    "conditions": [
                        {
                            "type": "Succeeded",
                            "status": "True",
                            "reason": "Succeeded",
                            "message": "",
                            "lastTransitionTime": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        }
                    ],
                }
            }
            for attempt in range(5):
                try:
                    k8s_api.patch_namespaced_custom_object(
                        group=_IR_GROUP,
                        version=_IR_VERSION,
                        namespace=namespace,
                        plural=_IR_PLURAL,
                        name=ir_name,
                        body=patch,
                        _content_type="application/merge-patch+json",
                    )
                    break
                except Exception as e:
                    if attempt == 4:
                        print(f"ERROR: Failed to patch {ir_name}: {e}", flush=True)
                    time.sleep(1)
        except Exception as e:
            print(f"ERROR in patch thread: {e}", flush=True)

    threading.Thread(target=_patch, daemon=True).start()


def create(pipeline, *, params, labels=None, sync=True, timeout=3600,
           service_account=None, pipeline_timeout="1h0m0s", task_timeout="0h55m0s",
           finally_timeout="0h5m0s", cleanup=True, k8s_api=None):
    """Mock create - creates InternalRequest and patches status asynchronously."""
    if k8s_api is None:
        k8s_api = _default_k8s_api()

    merged_labels = dict(labels or {})
    merged_labels["internal-services.appstudio.openshift.io/pipeline-name"] = pipeline

    payload = {
        "apiVersion": "appstudio.redhat.com/v1alpha1",
        "kind": "InternalRequest",
        "metadata": {"generateName": f"{pipeline}-", "labels": merged_labels},
        "spec": {
            "pipeline": {
                "pipelineRef": {
                    "resolver": "git",
                    "params": [
                        {"name": "url", "value": params.get("taskGitUrl", "")},
                        {"name": "revision", "value": params.get("taskGitRevision", "")},
                        {"name": "pathInRepo", "value": f"pipelines/internal/{pipeline}/{pipeline}.yaml"},
                    ],
                },
            },
            "params": dict(params),
            "timeouts": {"pipeline": pipeline_timeout, "tasks": task_timeout, "finally": finally_timeout},
        },
    }
    if service_account:
        payload["spec"]["serviceAccount"] = service_account

    namespace = _get_namespace()
    resource = k8s_api.create_namespaced_custom_object(
        group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, body=payload
    )
    ir_name = resource["metadata"]["name"]

    mock_results = _create_mock_results()
    _MOCK_RESULTS[ir_name] = mock_results
    _patch_status_async(ir_name, mock_results)

    return ir_name


def fetch_results(internal_request_name, *, k8s_api=None):
    """Mock fetch_results - returns stored mock results."""
    if internal_request_name in _MOCK_RESULTS:
        return _MOCK_RESULTS[internal_request_name]

    if k8s_api is None:
        k8s_api = _default_k8s_api()
    namespace = _get_namespace()
    resource = k8s_api.get_namespaced_custom_object(
        group=_IR_GROUP, version=_IR_VERSION, namespace=namespace, plural=_IR_PLURAL, name=internal_request_name
    )
    results = resource.get("status", {}).get("results")
    return results if isinstance(results, dict) else {}


# Create proxy module that delegates to real package but overrides internal_request
class _ProxyModule(ModuleType):
    """Proxy module that delegates to real package except for internal_request."""

    def __init__(self, name):
        super().__init__(name)
        # Make it look like a package by copying __path__ from real module
        if hasattr(_real_rsu, "__path__"):
            self.__path__ = _real_rsu.__path__
        self.__file__ = getattr(_real_rsu, "__file__", None)

    def __getattr__(self, name):
        if name == "helpers":
            # Return proxy helpers module
            return _proxy_helpers
        # Delegate everything else to real package
        return getattr(_real_rsu, name)


class _ProxyHelpers(ModuleType):
    """Proxy helpers module."""

    def __getattr__(self, name):
        if name == "internal_request":
            return _internal_request_mod
        # Delegate to real helpers
        return getattr(_real_rsu.helpers, name)


# Create mock internal_request module
_internal_request_mod = ModuleType("internal_request")
_internal_request_mod.InternalRequestWaitError = InternalRequestWaitError
_internal_request_mod.create = create
_internal_request_mod.fetch_results = fetch_results

# Create proxy modules
_proxy_helpers = _ProxyHelpers("helpers")
_proxy_rsu = _ProxyModule("release_service_utils")

# Inject into sys.modules
sys.modules["release_service_utils"] = _proxy_rsu
sys.modules["release_service_utils.helpers.internal_request"] = _internal_request_mod
