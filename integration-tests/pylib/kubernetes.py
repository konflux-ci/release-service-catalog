"""
Kubernetes client wrapper for integration tests.

Provides async-friendly methods for common Kubernetes operations
used in release pipeline testing.
"""

import asyncio
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException

from .utils import log_error, log_info, log_warning, wait_for_condition


@dataclass
class ResourceStatus:
    """Status of a Kubernetes custom resource (PipelineRun, Release, etc.)."""

    name: str
    namespace: str
    succeeded: bool | None  # None = still running
    reason: str
    message: str


class KubernetesClient:
    """
    Kubernetes client for integration test operations.

    Provides async wrappers around common K8s operations for:
    - Namespace verification
    - Component management
    - PipelineRun monitoring
    - Release monitoring
    - Resource CRUD operations
    """

    def __init__(self, kubeconfig: str | None = None):
        """
        Initialize the Kubernetes client.

        Args:
            kubeconfig: Optional path to kubeconfig file.
        """
        if kubeconfig:
            config.load_kube_config(config_file=kubeconfig)
        else:
            try:
                config.load_incluster_config()
            except config.ConfigException:
                config.load_kube_config()

        self.core_v1 = client.CoreV1Api()
        self.custom_objects = client.CustomObjectsApi()
        self.apps_v1 = client.AppsV1Api()

    # -------------------------------------------------------------------------
    # Namespace Operations
    # -------------------------------------------------------------------------

    async def namespace_exists(self, namespace: str) -> bool:
        """Check if a namespace exists."""
        try:
            await asyncio.to_thread(self.core_v1.read_namespace, namespace)
            return True
        except ApiException as e:
            if e.status == 404:
                return False
            raise

    async def set_current_namespace(self, namespace: str) -> None:
        """Set the current namespace context."""
        contexts, active_context = config.list_kube_config_contexts()
        if active_context:
            active_context["context"]["namespace"] = namespace
            log_info(f"Set current namespace to {namespace}")

    # -------------------------------------------------------------------------
    # YAML Resource Operations
    # -------------------------------------------------------------------------

    async def kubectl_yaml(
        self, action: str, yaml_content: str, namespace: str
    ) -> None:
        """
        Run a kubectl action on YAML content.

        Args:
            action: One of "apply", "create", or "delete".
            yaml_content: The YAML content to act on.
            namespace: Target namespace.
        """
        import tempfile

        import yaml as pyyaml

        from .utils import run_command

        # Parse YAML to list resources being acted on
        resources = []
        for doc in pyyaml.safe_load_all(yaml_content):
            if doc:
                kind = doc.get("kind", "Unknown")
                name = doc.get("metadata", {}).get("name", "unknown")
                resources.append(f"{kind}/{name}")

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".yaml", delete=False
        ) as f:
            f.write(yaml_content)
            f.flush()
            temp_path = f.name

        try:
            check = action != "delete"  # Don't fail on delete errors
            await run_command(
                ["kubectl", action, "-f", temp_path, "-n", namespace],
                check=check,
            )
            past_tense = {"apply": "Applied", "create": "Created", "delete": "Deleted"}
            action_word = past_tense.get(action, action)
            for resource in resources:
                log_info(f"{action_word} {resource} in {namespace}")
        finally:
            Path(temp_path).unlink(missing_ok=True)

    # -------------------------------------------------------------------------
    # Component Operations
    # -------------------------------------------------------------------------

    async def get_component(self, name: str, namespace: str) -> dict[str, Any] | None:
        """Get an AppStudio Component custom resource."""
        try:
            result = await asyncio.to_thread(
                self.custom_objects.get_namespaced_custom_object,
                group="appstudio.redhat.com",
                version="v1alpha1",
                namespace=namespace,
                plural="components",
                name=name,
            )
            return result
        except ApiException as e:
            if e.status == 404:
                return None
            raise

    async def get_component_pr_url(self, name: str, namespace: str) -> str | None:
        """
        Get the PR URL from a Component's annotations.

        Returns the merge-url from build.appstudio.openshift.io/status annotation.
        """
        component = await self.get_component(name, namespace)
        if not component:
            return None

        annotations = component.get("metadata", {}).get("annotations", {})
        status_json = annotations.get("build.appstudio.openshift.io/status", "")

        if not status_json:
            return None

        try:
            status = json.loads(status_json)
            return status.get("pac", {}).get("merge-url")
        except json.JSONDecodeError:
            log_warning(f"Failed to parse component status JSON: {status_json}")
            return None

    async def wait_for_component_initialization(
        self,
        name: str,
        namespace: str,
        timeout_seconds: int = 600,
    ) -> str:
        """
        Wait for a Component to be initialized and return its PR URL.

        Args:
            name: Component name.
            namespace: Namespace.
            timeout_seconds: Maximum time to wait.

        Returns:
            The PR URL for the component.

        Raises:
            TimeoutError: If component doesn't initialize in time.
        """

        async def check_initialized() -> str | None:
            return await self.get_component_pr_url(name, namespace)

        pr_url = await wait_for_condition(
            check_initialized,
            timeout_seconds=timeout_seconds,
            interval_seconds=10,
            description=f"Component {name} initialization",
        )

        log_info(f"Component {name} initialized with PR: {pr_url}")
        return pr_url

    async def annotate_component(
        self, name: str, namespace: str, annotation: str, value: str
    ) -> None:
        """Add an annotation to a Component."""
        from .utils import run_command

        await run_command(
            [
                "kubectl",
                "annotate",
                f"components/{name}",
                f"{annotation}={value}",
                "-n",
                namespace,
            ]
        )
        log_info(f"Annotated component {name} with {annotation}={value}")

    async def trigger_component_rebuild(self, name: str, namespace: str) -> None:
        """Trigger a rebuild for a Component."""
        await self.annotate_component(
            name,
            namespace,
            "build.appstudio.openshift.io/request",
            "trigger-pac-build",
        )

    # -------------------------------------------------------------------------
    # PipelineRun Operations
    # -------------------------------------------------------------------------

    async def get_pipelineruns_by_sha(
        self, sha: str, namespace: str
    ) -> list[dict[str, Any]]:
        """Get PipelineRuns with a specific SHA label."""
        result = await asyncio.to_thread(
            self.custom_objects.list_namespaced_custom_object,
            group="tekton.dev",
            version="v1",
            namespace=namespace,
            plural="pipelineruns",
            label_selector=f"pipelinesascode.tekton.dev/sha={sha}",
        )
        return result.get("items", [])

    async def get_pipelineruns_by_label(
        self, label_selector: str, namespace: str
    ) -> list[dict[str, Any]]:
        """Get PipelineRuns matching a label selector."""
        result = await asyncio.to_thread(
            self.custom_objects.list_namespaced_custom_object,
            group="tekton.dev",
            version="v1",
            namespace=namespace,
            plural="pipelineruns",
            label_selector=label_selector,
        )
        return result.get("items", [])

    async def wait_for_pipelinerun(
        self,
        sha: str,
        namespace: str,
        timeout_seconds: int = 300,
    ) -> str:
        """
        Wait for a PipelineRun to appear for a given SHA.

        Returns the PipelineRun name.
        """

        async def check_plr() -> str | None:
            plrs = await self.get_pipelineruns_by_sha(sha, namespace)
            for plr in plrs:
                conditions = (
                    plr.get("status", {}).get("conditions", [])
                    if plr.get("status")
                    else []
                )
                for cond in conditions:
                    if cond.get("type") == "Succeeded" and cond.get("status") == "Unknown":
                        return plr["metadata"]["name"]
                if not conditions:
                    return plr["metadata"]["name"]
            return None

        plr_name = await wait_for_condition(
            check_plr,
            timeout_seconds=timeout_seconds,
            interval_seconds=5,
            description=f"PipelineRun for SHA {sha[:8]}",
        )

        log_info(f"Found PipelineRun: {plr_name}")
        return plr_name

    async def get_pipelinerun_status(
        self, name: str, namespace: str
    ) -> ResourceStatus:
        """Get the status of a PipelineRun."""
        result = await asyncio.to_thread(
            self.custom_objects.get_namespaced_custom_object,
            group="tekton.dev",
            version="v1",
            namespace=namespace,
            plural="pipelineruns",
            name=name,
        )

        conditions = result.get("status", {}).get("conditions", [])

        succeeded = None
        reason = ""
        message = ""

        for cond in conditions:
            if cond.get("type") == "Succeeded":
                status = cond.get("status")
                if status == "True":
                    succeeded = True
                elif status == "False":
                    succeeded = False
                reason = cond.get("reason", "")
                message = cond.get("message", "")
                break

        return ResourceStatus(
            name=name,
            namespace=namespace,
            succeeded=succeeded,
            reason=reason,
            message=message,
        )

    async def wait_for_pipelinerun_completion(
        self,
        name: str,
        namespace: str,
        timeout_seconds: int = 1800,
    ) -> ResourceStatus:
        """Wait for a PipelineRun to complete. Returns the final status."""

        async def check_completed() -> ResourceStatus | None:
            status = await self.get_pipelinerun_status(name, namespace)
            if status.succeeded is not None:
                return status
            print(f"PipelineRun {name}: {status.reason}")
            return None

        status = await wait_for_condition(
            check_completed,
            timeout_seconds=timeout_seconds,
            interval_seconds=10,
            description=f"PipelineRun {name} completion",
        )

        if status.succeeded:
            log_info(f"PipelineRun {name} succeeded")
        else:
            log_error(f"PipelineRun {name} failed: {status.message}")

        return status

    # -------------------------------------------------------------------------
    # Release Operations
    # -------------------------------------------------------------------------

    async def get_releases_by_pipelinerun(
        self, plr_name: str, namespace: str
    ) -> list[dict[str, Any]]:
        """Get Release resources associated with a PipelineRun."""
        result = await asyncio.to_thread(
            self.custom_objects.list_namespaced_custom_object,
            group="appstudio.redhat.com",
            version="v1alpha1",
            namespace=namespace,
            plural="releases",
            label_selector=f"appstudio.openshift.io/build-pipelinerun={plr_name}",
        )
        return result.get("items", [])

    async def wait_for_releases(
        self,
        plr_name: str,
        namespace: str,
        timeout_seconds: int = 300,
    ) -> list[str]:
        """Wait for Release resources to appear for a PipelineRun."""

        async def check_releases() -> list[str] | None:
            releases = await self.get_releases_by_pipelinerun(plr_name, namespace)
            if releases:
                return [r["metadata"]["name"] for r in releases]
            return None

        release_names = await wait_for_condition(
            check_releases,
            timeout_seconds=timeout_seconds,
            interval_seconds=5,
            description=f"Releases for PipelineRun {plr_name}",
        )

        log_info(f"Found releases: {', '.join(release_names)}")
        return release_names

    async def get_release(self, name: str, namespace: str) -> dict[str, Any] | None:
        """Get a Release custom resource."""
        try:
            result = await asyncio.to_thread(
                self.custom_objects.get_namespaced_custom_object,
                group="appstudio.redhat.com",
                version="v1alpha1",
                namespace=namespace,
                plural="releases",
                name=name,
            )
            return result
        except ApiException as e:
            if e.status == 404:
                return None
            raise

    async def get_release_status(self, name: str, namespace: str) -> ResourceStatus:
        """Get the status of a Release."""
        release = await self.get_release(name, namespace)
        if not release:
            raise ValueError(f"Release {name} not found in namespace {namespace}")

        conditions = release.get("status", {}).get("conditions", [])

        succeeded = None
        reason = ""
        message = ""

        # Find the Released condition
        for cond in conditions:
            if cond.get("type") == "Released":
                status_val = cond.get("status")
                reason = cond.get("reason", "")
                message = cond.get("message", "")

                if status_val == "True":
                    succeeded = True
                elif status_val == "False":
                    # Only treat as failed if reason indicates actual failure
                    # "Progressing" means still in progress, not failed
                    if reason in ("Progressing", "Running", "Pending"):
                        succeeded = None  # Still in progress
                    else:
                        succeeded = False  # Actually failed
                break

        return ResourceStatus(
            name=name,
            namespace=namespace,
            succeeded=succeeded,
            reason=reason,
            message=message,
        )

    async def wait_for_release_completion(
        self,
        name: str,
        namespace: str,
        timeout_seconds: int = 1800,
    ) -> ResourceStatus:
        """Wait for a Release to complete. Returns the final status."""

        async def check_completed() -> ResourceStatus | None:
            status = await self.get_release_status(name, namespace)
            if status.succeeded is not None:
                return status
            print(f"Release {name}: {status.reason or 'waiting...'}")
            return None

        status = await wait_for_condition(
            check_completed,
            timeout_seconds=timeout_seconds,
            interval_seconds=10,
            description=f"Release {name} completion",
        )

        if status.succeeded:
            log_info(f"Release {name} completed: {status.reason}")
        else:
            log_error(f"Release {name} failed: {status.reason} - {status.message}")

        return status

    async def create_release(
        self,
        name: str,
        namespace: str,
        snapshot: str,
        release_plan: str,
    ) -> dict[str, Any]:
        """
        Create a Release custom resource.

        Useful for tests that trigger manual releases.
        """
        release_manifest = {
            "apiVersion": "appstudio.redhat.com/v1alpha1",
            "kind": "Release",
            "metadata": {
                "name": name,
                "namespace": namespace,
            },
            "spec": {
                "snapshot": snapshot,
                "releasePlan": release_plan,
            },
        }

        result = await asyncio.to_thread(
            self.custom_objects.create_namespaced_custom_object,
            group="appstudio.redhat.com",
            version="v1alpha1",
            namespace=namespace,
            plural="releases",
            body=release_manifest,
        )

        log_info(f"Created Release {name} in namespace {namespace}")
        return result

    # -------------------------------------------------------------------------
    # Snapshot Operations
    # -------------------------------------------------------------------------

    async def get_snapshots(
        self, namespace: str, application: str
    ) -> list[dict[str, Any]]:
        """Get Snapshots for an application."""
        result = await asyncio.to_thread(
            self.custom_objects.list_namespaced_custom_object,
            group="appstudio.redhat.com",
            version="v1alpha1",
            namespace=namespace,
            plural="snapshots",
            label_selector=f"appstudio.openshift.io/application={application}",
        )
        return result.get("items", [])

    async def get_snapshot_by_component_count(
        self,
        namespace: str,
        application: str,
        component_count: int,
    ) -> dict[str, Any] | None:
        """Get the most recent Snapshot with a specific number of components."""
        snapshots = await self.get_snapshots(namespace, application)

        # Sort by creation timestamp (newest first)
        snapshots.sort(
            key=lambda s: s.get("metadata", {}).get("creationTimestamp", ""),
            reverse=True,
        )

        for snapshot in snapshots:
            components = snapshot.get("spec", {}).get("components", [])
            if len(components) == component_count:
                return snapshot

        return None

    # -------------------------------------------------------------------------
    # Utility Methods
    # -------------------------------------------------------------------------

    def get_console_url(self) -> str | None:
        """
        Get the console URL from the kubeconfig.

        Derives the Konflux UI URL from the API server URL.
        """
        try:
            contexts, active_context = config.list_kube_config_contexts()
            if not active_context:
                return None

            # Get cluster server from current context
            from .utils import run_command
            import subprocess

            result = subprocess.run(
                [
                    "kubectl",
                    "config",
                    "view",
                    "--minify",
                    "--output",
                    "jsonpath={.clusters[*].cluster.server}",
                ],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                return None

            server_url = result.stdout.strip()
            # Transform api.xxx to konflux-ui.apps.xxx
            console_url = server_url.replace("api.", "konflux-ui.apps.")
            console_url = console_url.replace(":6443", "")
            return console_url.rstrip("/")
        except Exception:
            return None

    def get_pipelinerun_url(
        self, namespace: str, application: str, plr_name: str
    ) -> str | None:
        """Get the console URL for a PipelineRun."""
        console_url = self.get_console_url()
        if not console_url:
            return None
        return f"{console_url}/ns/{namespace}/applications/{application}/pipelineruns/{plr_name}"

    def get_release_url(
        self, namespace: str, application: str, release_name: str
    ) -> str | None:
        """Get the console URL for a Release."""
        console_url = self.get_console_url()
        if not console_url:
            return None
        return f"{console_url}/ns/{namespace}/applications/{application}/releases/{release_name}"
