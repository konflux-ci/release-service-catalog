"""
Base pytest configuration and fixtures for integration tests.

This module provides generic fixtures that can be used by any test suite.
Test suites should import these and add their own test_config fixture.

Usage in a test suite's conftest.py:

    from pylib.conftest_base import *  # Import all generic fixtures
    from my_suite.lib.config import MyTestConfig

    @pytest.fixture(scope="session")
    def test_config(suite_dir: Path, skip_cleanup: bool) -> MyTestConfig:
        config = MyTestConfig.from_test_env(suite_dir)
        config.cleanup = not skip_cleanup
        return config
"""

import asyncio
from pathlib import Path
from typing import AsyncGenerator

import pytest
import pytest_asyncio

from .config import TestConfigBase
from .github import GitHubClient, copy_branch_to_repo, delete_repository
from .kubernetes import KubernetesClient
from .resources import ResourceManager
from .vault import cleanup_decrypted_secrets, decrypt_secrets
from .utils import log_error, log_info, log_warning


def pytest_addoption(parser: pytest.Parser) -> None:
    """Add custom command line options."""
    parser.addoption(
        "--skip-cleanup",
        action="store_true",
        default=False,
        help="Skip cleanup of resources after test",
    )


@pytest.fixture(scope="session")
def suite_dir() -> Path:
    """
    Return the path to the test suite directory.
    
    Override this in your conftest.py if needed.
    """
    # This will be overridden by each test suite
    raise NotImplementedError("suite_dir fixture must be defined in test suite conftest.py")


@pytest.fixture(scope="session")
def scripts_dir(suite_dir: Path) -> Path:
    """Return the path to the scripts directory."""
    return suite_dir.parent / "scripts"


@pytest.fixture(scope="session")
def skip_cleanup(request: pytest.FixtureRequest) -> bool:
    """Return whether to skip cleanup."""
    return request.config.getoption("--skip-cleanup")


@pytest.fixture(scope="session")
def k8s_client(test_config: TestConfigBase) -> KubernetesClient:
    """Create a Kubernetes client."""
    return KubernetesClient(kubeconfig=test_config.kubeconfig)


@pytest.fixture(scope="session")
def github_client(test_config: TestConfigBase) -> GitHubClient:
    """Create a GitHub client."""
    return GitHubClient(token=test_config.github_token)


@pytest_asyncio.fixture(scope="session")
async def decrypted_secrets(
    suite_dir: Path,
    test_config: TestConfigBase,
    skip_cleanup: bool,
) -> AsyncGenerator[None, None]:
    """Decrypt secrets before tests and optionally clean up after."""
    await decrypt_secrets(suite_dir, test_config.vault_password_file)
    yield
    if not skip_cleanup:
        await cleanup_decrypted_secrets(suite_dir)


@pytest_asyncio.fixture(scope="session")
async def github_repository(
    test_config: TestConfigBase,
    scripts_dir: Path,
    skip_cleanup: bool,
) -> AsyncGenerator[str, None]:
    """Create the GitHub repository for testing."""
    repo_name = test_config.component_repo_name

    log_info(f"Creating repository {repo_name}")
    await copy_branch_to_repo(
        test_config.component_base_repo_name,
        test_config.component_base_branch,
        repo_name,
        test_config.component_branch,
        str(scripts_dir),
    )

    yield repo_name

    if not skip_cleanup:
        log_info(f"Cleaning up repository {repo_name}")
        await delete_repository(repo_name, str(scripts_dir))


@pytest_asyncio.fixture(scope="session")
async def verified_namespaces(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
) -> None:
    """Verify that required namespaces exist."""
    for ns in [test_config.tenant_namespace, test_config.managed_namespace]:
        if not await k8s_client.namespace_exists(ns):
            raise RuntimeError(f"Required namespace {ns} does not exist")
        log_info(f"Verified namespace exists: {ns}")

    await k8s_client.set_current_namespace(test_config.tenant_namespace)


@pytest_asyncio.fixture(scope="session")
async def kubernetes_resources(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    suite_dir: Path,
    decrypted_secrets: None,
    verified_namespaces: None,
    skip_cleanup: bool,
) -> AsyncGenerator[ResourceManager, None]:
    """Create Kubernetes resources for testing."""
    resource_manager = ResourceManager(k8s_client, test_config, suite_dir)

    await resource_manager.create_resources()

    yield resource_manager

    if not skip_cleanup:
        log_info("Cleaning up Kubernetes resources")
        await resource_manager.cleanup_resources()


@pytest_asyncio.fixture(scope="session")
async def initialized_component(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    github_repository: str,
    kubernetes_resources: ResourceManager,
) -> tuple[str, int]:
    """Wait for the component to be initialized. Returns (pr_url, pr_number)."""
    pr_url = await k8s_client.wait_for_component_initialization(
        test_config.component_name,
        test_config.tenant_namespace,
        timeout_seconds=600,
    )

    pr_number = int(pr_url.split("/")[-1])
    return pr_url, pr_number


@pytest_asyncio.fixture(scope="session")
async def merged_pr(
    github_client: GitHubClient,
    test_config: TestConfigBase,
    initialized_component: tuple[str, int],
) -> str:
    """Merge the component PR. Returns the merge commit SHA."""
    pr_url, pr_number = initialized_component

    # Use CVE message if configured
    commit_message = "e2e test"
    if hasattr(test_config, 'no_cve') and not test_config.no_cve:
        commit_message = "This fixes CVE-2024-8260"

    result = await github_client.merge_pr(
        test_config.component_repo_name,
        pr_number,
        commit_title="e2e test",
        commit_message=commit_message,
    )

    if not result.merged:
        raise RuntimeError(f"Failed to merge PR: {result.message}")

    return result.sha


@pytest_asyncio.fixture(scope="session")
async def pipelinerun(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    merged_pr: str,
) -> str:
    """Wait for the PipelineRun to appear. Returns the PipelineRun name."""
    return await k8s_client.wait_for_pipelinerun(
        merged_pr,
        test_config.tenant_namespace,
        timeout_seconds=300,
    )


@pytest_asyncio.fixture(scope="session")
async def completed_pipelinerun(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    pipelinerun: str,
) -> str:
    """Wait for the PipelineRun to complete."""
    status = await k8s_client.wait_for_pipelinerun_completion(
        pipelinerun,
        test_config.tenant_namespace,
        timeout_seconds=1800,
    )

    if not status.succeeded:
        log_warning(f"PipelineRun {pipelinerun} failed, attempting retry...")
        await k8s_client.trigger_component_rebuild(
            test_config.component_name,
            test_config.tenant_namespace,
        )

        raise RuntimeError(
            f"PipelineRun failed: {status.reason} - {status.message}"
        )

    return pipelinerun


@pytest_asyncio.fixture(scope="session")
async def releases(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    completed_pipelinerun: str,
) -> list[str]:
    """Wait for Releases to be created. Returns list of Release names."""
    return await k8s_client.wait_for_releases(
        completed_pipelinerun,
        test_config.tenant_namespace,
        timeout_seconds=300,
    )


@pytest_asyncio.fixture(scope="session")
async def completed_releases(
    k8s_client: KubernetesClient,
    test_config: TestConfigBase,
    releases: list[str],
) -> list[str]:
    """Wait for all Releases to complete."""
    tasks = [
        k8s_client.wait_for_release_completion(
            release_name,
            test_config.tenant_namespace,
            timeout_seconds=1800,
        )
        for release_name in releases
    ]

    results = await asyncio.gather(*tasks, return_exceptions=True)

    failed = []
    succeeded_releases = []
    for release_name, result in zip(releases, results):
        if isinstance(result, Exception):
            log_error(f"Release {release_name} failed with exception: {result}")
            failed.append(release_name)
        elif result.succeeded is None:
            log_error(f"Release {release_name} status unknown (still running?)")
            failed.append(release_name)
        elif not result.succeeded:
            log_error(f"Release {release_name} failed: {result.reason} - {result.message}")
            failed.append(release_name)
        else:
            log_info(f"Release {release_name} completed successfully")
            succeeded_releases.append(release_name)

    if failed:
        raise RuntimeError(f"Releases failed: {', '.join(failed)}")

    return succeeded_releases
