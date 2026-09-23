#!/usr/bin/env python3
"""
E2E Test Runner

Usage:
    ./run_test.py                    # Run the test
    ./run_test.py --skip-cleanup     # Skip cleanup after test
    ./run_test.py -v                 # Verbose output
"""

import sys
from pathlib import Path

# Add integration-tests directory to path for pylib imports
script_dir = Path(__file__).parent
integration_tests_dir = script_dir.parent
sys.path.insert(0, str(integration_tests_dir))

from pylib.runner import check_environment, create_argument_parser, run_pytest


def main() -> int:
    parser = create_argument_parser("Run E2E test for Release Service Catalog")
    args = parser.parse_args()

    if not check_environment():
        return 1

    return run_pytest(
        test_file=script_dir / "test_e2e.py",
        suite_dir=script_dir,
        skip_cleanup=args.skip_cleanup,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    sys.exit(main())
