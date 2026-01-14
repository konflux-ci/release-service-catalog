"""
Kubernetes resource management for integration tests.

Handles building and applying kustomize resources with variable substitution.
"""

import re
from pathlib import Path

from .config import TestConfigBase
from .kubernetes import KubernetesClient
from .utils import log_info, run_command


def substitute_env_vars(content: str, env_vars: dict[str, str]) -> str:
    """
    Substitute environment variables in content.

    Handles both $VAR and ${VAR} syntax, like envsubst.

    Args:
        content: String with variable references.
        env_vars: Dictionary of variable names to values.

    Returns:
        String with variables substituted.
    """
    def replace_var(match: re.Match) -> str:
        var_name = match.group(1) or match.group(2)
        return env_vars.get(var_name, match.group(0))

    # Match ${VAR} or $VAR (word characters only)
    pattern = r'\$\{(\w+)\}|\$(\w+)'
    return re.sub(pattern, replace_var, content)


async def build_kustomize_resources(
    resource_dir: Path,
    env_vars: dict[str, str],
) -> str:
    """
    Build kustomize resources with environment variable substitution.

    Args:
        resource_dir: Path to the kustomize directory.
        env_vars: Environment variables to substitute.

    Returns:
        The processed YAML content.
    """
    # Run kustomize build
    _, kustomize_output, _ = await run_command(
        ["kustomize", "build", str(resource_dir)]
    )

    # Substitute environment variables (like envsubst)
    return substitute_env_vars(kustomize_output, env_vars)


class ResourceManager:
    """
    Manages Kubernetes resources for a test run.

    Handles creation and cleanup of test resources using kustomize.
    """

    def __init__(
        self,
        k8s_client: KubernetesClient,
        config: TestConfigBase,
        suite_dir: Path,
    ):
        """
        Initialize the resource manager.

        Args:
            k8s_client: Kubernetes client.
            config: Test configuration.
            suite_dir: Path to the test suite directory.
        """
        self.k8s = k8s_client
        self.config = config
        self.suite_dir = suite_dir
        self.tenant_resources_yaml: str | None = None
        self.managed_resources_yaml: str | None = None

    async def create_resources(self) -> None:
        """Create all Kubernetes resources for the test."""
        env_vars = self.config.get_env_dict()

        # Build and apply tenant resources
        tenant_dir = self.suite_dir / "resources" / "tenant"
        if tenant_dir.exists():
            self.tenant_resources_yaml = await build_kustomize_resources(
                tenant_dir, env_vars
            )
            await self.k8s.kubectl_yaml(
                "create",
                self.tenant_resources_yaml,
                self.config.tenant_namespace,
            )

        # Build and apply managed resources
        managed_dir = self.suite_dir / "resources" / "managed"
        if managed_dir.exists():
            self.managed_resources_yaml = await build_kustomize_resources(
                managed_dir, env_vars
            )
            # Use apply to avoid conflicts when running tests in parallel
            await self.k8s.kubectl_yaml(
                "apply",
                self.managed_resources_yaml,
                self.config.managed_namespace,
            )

    async def cleanup_resources(self) -> None:
        """Delete all Kubernetes resources created for the test."""
        if self.tenant_resources_yaml:
            await self.k8s.kubectl_yaml(
                "delete",
                self.tenant_resources_yaml,
                self.config.tenant_namespace,
            )

        if self.managed_resources_yaml:
            await self.k8s.kubectl_yaml(
                "delete",
                self.managed_resources_yaml,
                self.config.managed_namespace,
            )

    async def save_resources_for_debug(self, output_dir: Path) -> None:
        """Save the generated resources to files for debugging."""
        output_dir.mkdir(parents=True, exist_ok=True)

        if self.tenant_resources_yaml:
            (output_dir / "tenant-resources.yaml").write_text(
                self.tenant_resources_yaml
            )

        if self.managed_resources_yaml:
            (output_dir / "managed-resources.yaml").write_text(
                self.managed_resources_yaml
            )

        log_info(f"Saved resources to {output_dir}")
