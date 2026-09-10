"""
Shared Python Library for Integration Tests

This module provides reusable utilities for all integration test suites:
- Kubernetes client operations
- GitHub API interactions
- Secret management
- Resource building and management
- Logging and retry utilities
- Reusable pytest fixtures

Usage:
    from pylib import KubernetesClient, GitHubClient, TestConfigBase

For fixtures in conftest.py:
    from pylib.conftest_base import *  # Import all generic fixtures
"""

from .config import TestConfigBase
from .github import GitHubClient, copy_branch_to_repo, delete_repository
from .kubernetes import KubernetesClient, ResourceStatus
from .resources import ResourceManager, build_kustomize_resources
from .vault import cleanup_decrypted_secrets, decrypt_secrets
from .utils import (
    log_error,
    log_info,
    log_warning,
    run_command,
    run_with_retry,
    wait_for_condition,
)

__all__ = [
    # Config
    "TestConfigBase",
    # Kubernetes
    "KubernetesClient",
    "ResourceStatus",
    # GitHub
    "GitHubClient",
    "copy_branch_to_repo",
    "delete_repository",
    # Resources
    "ResourceManager",
    "build_kustomize_resources",
    # Secrets
    "decrypt_secrets",
    "cleanup_decrypted_secrets",
    # Utils
    "log_info",
    "log_error",
    "log_warning",
    "wait_for_condition",
    "run_command",
    "run_with_retry",
]
