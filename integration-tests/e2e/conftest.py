"""
Pytest configuration for E2E tests.

Imports generic fixtures from the shared library and adds e2e-specific config.
"""

import sys
from pathlib import Path

import pytest

# Add integration-tests directory to path
suite_dir_path = Path(__file__).parent
integration_tests_dir = suite_dir_path.parent
sys.path.insert(0, str(integration_tests_dir))

# Import all generic fixtures from shared library
from pylib.conftest_base import *  # noqa: F401, F403

# Import e2e-specific config
from e2e.lib.config import E2EConfig

from pylib.utils import log_info


def pytest_sessionstart(session: pytest.Session) -> None:
    """Log when test session starts."""
    log_info("Starting E2E test session...")


@pytest.fixture(scope="session")
def suite_dir() -> Path:
    """Return the path to the e2e test suite directory."""
    return Path(__file__).parent


@pytest.fixture(scope="session")
def test_config(suite_dir: Path, skip_cleanup: bool) -> E2EConfig:
    """Load e2e test configuration."""
    config = E2EConfig.from_test_env(suite_dir)
    config.cleanup = not skip_cleanup
    log_info(f"E2E test configuration loaded with UUID: {config.uuid}")
    return config
