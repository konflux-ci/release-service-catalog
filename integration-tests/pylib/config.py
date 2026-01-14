"""
Base test configuration management.

Provides a base configuration class that test suites can extend
with their specific settings.
"""

import os
import secrets
import subprocess
from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings


def generate_uuid() -> str:
    """Generate an 8-character hex UUID."""
    return secrets.token_hex(4)


class TestConfigBase(BaseSettings):
    """
    Base test configuration loaded from environment variables.

    Test suites should subclass this and add their specific configuration.

    Example:
        class FBCReleaseConfig(TestConfigBase):
            # FBC-specific settings
            fbc_fragment_image: str = "quay.io/..."
            target_index: str = "..."
    """

    # Generated at runtime
    uuid: str = Field(default_factory=generate_uuid)

    # Core environment variables (required for all tests)
    github_token: str = Field(alias="GITHUB_TOKEN")
    vault_password_file: str = Field(alias="VAULT_PASSWORD_FILE")
    release_catalog_git_url: str = Field(alias="RELEASE_CATALOG_GIT_URL")
    release_catalog_git_revision: str = Field(alias="RELEASE_CATALOG_GIT_REVISION")

    # Optional environment variables
    kubeconfig: Optional[str] = Field(default=None, alias="KUBECONFIG")
    pr_number: Optional[str] = Field(default=None, alias="PR_NUMBER")

    # Common test configuration with sensible defaults
    originating_tool: str = "integration-test"
    tenant_namespace: str = "dev-release-team-tenant"
    managed_namespace: str = "managed-release-team-tenant"

    # Component configuration (can be overridden by subclasses)
    component_type: str = "test"
    component_github_org: str = "hacbs-release-tests"
    component_base_branch: str = "main"
    component_base_repo_name: str = ""

    # Runtime options
    cleanup: bool = True
    no_cve: bool = True  # Default to skipping CVE; tests that need CVE set this to False

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }

    @property
    def application_name(self) -> str:
        """Application name with UUID suffix."""
        return f"{self.component_type}-app-{self.uuid}"

    @property
    def component_name(self) -> str:
        """Component name with UUID suffix."""
        return f"{self.component_type}-{self.uuid}"

    @property
    def component_branch(self) -> str:
        """Branch name for the component (defaults to component_name)."""
        return self.component_name

    @property
    def appstudio_component_branch(self) -> str:
        """The branch name that AppStudio/Konflux creates."""
        return f"appstudio-{self.component_name}"

    @property
    def component_repo_name(self) -> str:
        """Full GitHub repository name (org/repo)."""
        return f"{self.component_github_org}/{self.component_name}"

    @property
    def component_git_url(self) -> str:
        """HTTPS URL to the component repository."""
        return f"https://github.com/{self.component_repo_name}"

    @property
    def tenant_sa_name(self) -> str:
        """Service account name in tenant namespace."""
        return f"{self.component_type}-sa-{self.uuid}"

    @property
    def managed_sa_name(self) -> str:
        """Service account name in managed namespace."""
        return f"{self.component_type}-sa-{self.uuid}"

    @property
    def release_plan_name(self) -> str:
        """ReleasePlan name."""
        return f"{self.component_type}-rp-{self.uuid}"

    @property
    def release_plan_admission_name(self) -> str:
        """ReleasePlanAdmission name."""
        return f"{self.component_type}-rpa-{self.uuid}"

    def get_env_dict(self) -> dict[str, str]:
        """
        Return environment variables for use with envsubst/kustomize.

        Subclasses can override to add additional variables.
        """
        return {
            "uuid": self.uuid,
            "originating_tool": self.originating_tool,
            "tenant_namespace": self.tenant_namespace,
            "managed_namespace": self.managed_namespace,
            "application_name": self.application_name,
            "component_type": self.component_type,
            "component_name": self.component_name,
            "component_branch": self.component_branch,
            "appstudio_component_branch": self.appstudio_component_branch,
            "component_github_org": self.component_github_org,
            "component_base_branch": self.component_base_branch,
            "component_repo_name": self.component_repo_name,
            "component_base_repo_name": self.component_base_repo_name,
            "component_git_url": self.component_git_url,
            "tenant_sa_name": self.tenant_sa_name,
            "managed_sa_name": self.managed_sa_name,
            "release_plan_name": self.release_plan_name,
            "release_plan_admission_name": self.release_plan_admission_name,
            "RELEASE_CATALOG_GIT_URL": self.release_catalog_git_url,
            "RELEASE_CATALOG_GIT_REVISION": self.release_catalog_git_revision,
        }

    @classmethod
    def load_test_env(cls, suite_dir: Path) -> None:
        """
        Source a bash test.env file and export its variables.

        This provides compatibility with existing bash-based test.env files.
        Call this before creating the config instance.

        Args:
            suite_dir: Path to the test suite directory containing test.env.
        """
        test_env_file = suite_dir / "test.env"

        if test_env_file.exists():
            # Source the bash test.env and extract exported variables
            # This handles bash variable expansion like ${uuid:-"..."}
            cmd = f"set -a && source {test_env_file} && env"
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                executable="/bin/bash",
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "=" in line:
                        key, _, value = line.partition("=")
                        # Only set if not already in environment
                        if key not in os.environ:
                            os.environ[key] = value

    @classmethod
    def from_test_env(cls, suite_dir: Path) -> "TestConfigBase":
        """
        Load configuration, sourcing test.env shell variables first.

        Args:
            suite_dir: Path to the test suite directory.

        Returns:
            Configured instance.
        """
        cls.load_test_env(suite_dir)
        return cls()
