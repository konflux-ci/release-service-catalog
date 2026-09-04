"""
E2E Test Configuration.

Extends the base configuration with e2e-specific settings.
"""

import sys
from pathlib import Path

# Add integration-tests directory to path
integration_tests_dir = Path(__file__).parent.parent.parent
sys.path.insert(0, str(integration_tests_dir))

from pylib.config import TestConfigBase


class E2EConfig(TestConfigBase):
    """
    E2E test configuration.

    This simple test just verifies the basic release workflow works.
    """

    # E2E-specific defaults
    originating_tool: str = "simple-e2e-test"
    component_type: str = "simple-e2e"
    component_base_branch: str = "simple-e2e-base"
    component_base_repo_name: str = "hacbs-release-tests/e2e-base"

    @property
    def application_name(self) -> str:
        """Application name - matches bash test.env pattern."""
        return f"e2e-app-{self.uuid}"
