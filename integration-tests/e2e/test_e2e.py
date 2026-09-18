"""
E2E Test for Release Service Catalog

This test verifies the complete release workflow:
1. Create GitHub repository from template
2. Create Kubernetes resources (Application, Component, ReleasePlan, etc.)
3. Wait for Component initialization (PAC creates PR)
4. Merge the PR to trigger build
5. Wait for PipelineRun to complete
6. Wait for Release to be created and complete
7. Verify Release contents

Usage:
    ./run_test.py
    ./run_test.py --skip-cleanup  # Keep resources for debugging
"""

import json
import sys
from pathlib import Path

import pytest

# Add integration-tests directory to path
integration_tests_dir = Path(__file__).parent.parent
sys.path.insert(0, str(integration_tests_dir))

from pylib.kubernetes import KubernetesClient
from pylib.utils import log_info

# Import e2e config
from e2e.lib.config import E2EConfig


@pytest.mark.asyncio
async def test_e2e_release(
    k8s_client: KubernetesClient,
    test_config: E2EConfig,
    completed_releases: list[str],
) -> None:
    """
    End-to-end test for the simple release pipeline.

    This test relies on fixtures to perform the setup steps:
    - Create GitHub repository
    - Create Kubernetes resources
    - Wait for component initialization
    - Merge PR
    - Wait for PipelineRun completion
    - Wait for Release completion

    The test then verifies the Release contents are correct.
    """
    log_info("Verifying release contents...")

    assert completed_releases, "No releases were created"

    for release_name in completed_releases:
        log_info(f"Verifying Release {release_name} in namespace {test_config.tenant_namespace}")

        release = await k8s_client.get_release(
            release_name,
            test_config.tenant_namespace,
        )

        assert release is not None, f"Release {release_name} not found"

        # Verify release succeeded
        status = await k8s_client.get_release_status(
            release_name,
            test_config.tenant_namespace,
        )

        assert status.succeeded, (
            f"Release {release_name} failed: {status.reason} - {status.message}"
        )

        # Log release details
        release_json = json.dumps(release, indent=2)
        log_info(f"Release JSON: {release_json}")

        log_info(f"✅ All release checks passed for {release_name}")

    log_info("✅ Success!")
