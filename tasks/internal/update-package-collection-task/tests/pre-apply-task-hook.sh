#!/usr/bin/env bash
set -euo pipefail

# This script is executed by the e2e-test-runner script before applying the
# Tekton TaskRun that's being tested.

# Make the mock scripts executable
chmod +x "$(dirname "$0")/mocks.sh"
