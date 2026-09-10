"""
Test runner utilities.

Common functions used by test runner scripts across all test suites.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


# Required environment variables for all tests
REQUIRED_ENV_VARS = [
    "GITHUB_TOKEN",
    "VAULT_PASSWORD_FILE",
    "RELEASE_CATALOG_GIT_URL",
    "RELEASE_CATALOG_GIT_REVISION",
]


def check_required_env_vars(
    additional_vars: list[str] | None = None,
) -> list[str]:
    """
    Check for required environment variables and return missing ones.

    Args:
        additional_vars: Additional test-specific required variables.

    Returns:
        List of missing variable names.
    """
    required = REQUIRED_ENV_VARS.copy()
    if additional_vars:
        required.extend(additional_vars)

    missing = []
    for var in required:
        if not os.environ.get(var):
            missing.append(var)

    return missing


def check_vault_password_file() -> bool:
    """
    Check if the vault password file exists.

    Returns:
        True if file exists or VAULT_PASSWORD_FILE is not set, False otherwise.
    """
    vault_file = os.environ.get("VAULT_PASSWORD_FILE")
    if vault_file and not Path(vault_file).exists():
        print(f"❌ VAULT_PASSWORD_FILE points to non-existent file: {vault_file}")
        return False
    return True


def check_environment(additional_vars: list[str] | None = None) -> bool:
    """
    Check all environment requirements.

    Args:
        additional_vars: Additional test-specific required variables.

    Returns:
        True if all checks pass, False otherwise.
    """
    print("🔍 Checking environment...")

    missing_vars = check_required_env_vars(additional_vars)
    if missing_vars:
        print("❌ Missing required environment variables:")
        for var in missing_vars:
            print(f"   - {var}")
        return False

    if not check_vault_password_file():
        return False

    # Check for KUBECONFIG (optional, just informational)
    kubeconfig = os.environ.get("KUBECONFIG")
    if kubeconfig:
        print(f"✅ Using KUBECONFIG: {kubeconfig}")
    else:
        print("⚠️  KUBECONFIG not set, using default kubectl config")

    print("✅ Environment check passed")
    return True


def create_argument_parser(description: str) -> argparse.ArgumentParser:
    """
    Create a standard argument parser with common options.

    Args:
        description: Description for the test runner.

    Returns:
        Configured ArgumentParser.
    """
    parser = argparse.ArgumentParser(description=description)

    parser.add_argument(
        "--skip-cleanup",
        "-sc",
        action="store_true",
        help="Skip cleanup of resources after test",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose output",
    )

    return parser


def run_pytest(
    test_file: Path,
    suite_dir: Path,
    skip_cleanup: bool = False,
    verbose: bool = False,
    extra_args: list[str] | None = None,
) -> int:
    """
    Run pytest for a test suite.

    Args:
        test_file: Path to the test file.
        suite_dir: Path to the test suite directory.
        skip_cleanup: Whether to skip cleanup.
        verbose: Whether to enable verbose output.
        extra_args: Additional pytest arguments.

    Returns:
        Exit code from pytest.
    """
    integration_tests_dir = suite_dir.parent
    pytest_ini = integration_tests_dir / "pylib" / "pytest.ini"

    pytest_args = [
        sys.executable,
        "-m",
        "pytest",
        "-s",  # Disable output capture - show logs immediately
        "-c", str(pytest_ini),
        str(test_file),
    ]

    if skip_cleanup:
        pytest_args.append("--skip-cleanup")

    if verbose:
        pytest_args.append("-v")

    if extra_args:
        pytest_args.extend(extra_args)

    print(f"\n🚀 Running: {' '.join(pytest_args)}\n")

    # Add PYTHONPATH to include the shared library
    env = os.environ.copy()
    python_path = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = f"{integration_tests_dir}:{python_path}" if python_path else str(integration_tests_dir)

    # Run pytest
    result = subprocess.run(pytest_args, cwd=suite_dir, env=env)

    if result.returncode == 0:
        print("\n✅ Test completed successfully")
    else:
        print(f"\n❌ Test failed with exit code {result.returncode}")

    return result.returncode
