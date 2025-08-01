#!/usr/bin/env bash
#
# run-test.sh - Main orchestrator for end-to-end release catalog pipeline testing.
#
# Overview:
#   This script executes a specific test suite for a release pipeline.
#   It simulates a complete workflow, including environment setup, secret
#   decryption, GitHub interactions (branching, PRs), Kubernetes resource
#   management (namespaces, CRs using kustomize/envsubst), monitoring of
#   Konflux Components and Tekton PipelineRuns, and finally, verification
#   of the Release custom resource.
#
#   The script is designed to be generic, with suite-specific configurations
#   and test logic loaded from a specified suite directory.
#
# Usage:
#   ./run-test.sh <suite_name> [options]
#
# Arguments:
#   <suite_name>          : (Required) The name of the test suite to execute.
#                           This corresponds to a subdirectory under the script's
#                           own directory (e.g., if script is in 'integration-tests',
#                           suite 'fbc-release' would be in 'integration-tests/fbc-release').
#                           This suite directory must contain:
#                             - test.env: Environment variables for the suite.
#                             - test.sh: Suite-specific test logic and functions.
#
# Options:
#   -sc, --skip-cleanup   : If set, the script will not perform cleanup operations
#                           (GitHub branches, Kubernetes resources) on exit.
#   -nocve, --no-cve      : If set, the script will not simulate the addition of a CVE.
#                           This affects commit messages and expected CVE data during
#                           release verification. Defaults to including CVE data.
#
# Environment Variables (Expected):
#   The script sources suite-specific environment variables from
#   `${SCRIPT_DIR}/<suite_name>/test.env`.
#   Key variables typically include (but are not limited to):
#     Required by the framework or common functions:
#       GITHUB_TOKEN                  - GitHub Personal Access Token.
#       VAULT_PASSWORD_FILE           - Path to Ansible Vault password file.
#       RELEASE_CATALOG_GIT_URL       - Git URL for the release service catalog.
#       RELEASE_CATALOG_GIT_REVISION  - Git revision for the release service catalog.
#     Required by specific test suites (examples):
#       component_branch              - Name of the component branch to create.
#       component_base_branch         - Base branch for the component branch.
#       component_repo_name           - GitHub repository name (e.g., "owner/repo").
#       managed_namespace             - Kubernetes namespace for managed resources.
#       tenant_namespace              - Kubernetes namespace for tenant resources (incl. Release CR).
#       application_name              - AppStudio Application name.
#       component_name                - AppStudio Component name.
#       managed_sa_name               - ServiceAccount in managed namespace (for advisory fetching).
#   Optional (globally recognized):
#     KUBECONFIG                    - Path to the Kubernetes configuration file.
#
# Dependencies:
#   External Commands:
#     - ansible-vault, kubectl, kustomize, envsubst, curl, jq, oc, tkn, yq, mktemp
#   Sourced Scripts (paths relative to this script's location):
#     - `<suite_name>/test.env`     : Suite-specific environment variables.
#                                     (Resolved to: ${SCRIPT_DIR}/<suite_name>/test.env)
#     - `<suite_name>/test.sh`      : Suite-specific test logic and functions.
#                                     (Resolved to: ${SCRIPT_DIR}/<suite_name>/test.sh)
#     - `lib/test-functions.sh`     : Common library functions for testing.
#                                     (Resolved to: ${SCRIPT_DIR}/lib/test-functions.sh)
#   Helper Scripts (typically called by functions in sourced scripts):
#     - Located in `../scripts/` relative to this script's directory.
#       (e.g., delete-single-branch.sh, create-branch-from-base.sh,
#        wait-for-release.sh, get-advisory-content.sh, etc.).
#
# Exit Behavior:
#   - Exits 0 on successful completion of all steps and verifications.
#   - Exits with a non-zero status code on error.
#   - A trap is set to call the 'cleanup_resources' function on EXIT,
#     regardless of success or failure (unless --skip-cleanup is used).
#     The cleanup function receives the exit code, line number, and command.
#


set -eo pipefail

suite=$1
if [ -z "$suite" ] ; then
  echo "🔴 error: missing parameter suite"
  exit 1
fi

# --- Configuration & Global Variables ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LIB_DIR="${SCRIPT_DIR}/lib"

SUITE_DIR="${SCRIPT_DIR}/${suite}" # e.g. "${SCRIPT_DIR}/fbc-release"

# Source environment variables (ensure this file exists and is correctly populated)
if [ -f "${SUITE_DIR}/test.env" ]; then
    . "${SUITE_DIR}/test.env"
else
    echo "error: test.env not found in ${SUITE_DIR}"
    exit 1
fi

# Source the function library
if [ -f "${LIB_DIR}/test-functions.sh" ]; then
    . "${LIB_DIR}/test-functions.sh"
else
    echo "error: Function library test-functions.sh not found in ${LIB_DIR}"
    exit 1
fi

# Source test script (ensure this file exists and is correctly populated)
if [ -f "${SUITE_DIR}/test.sh" ]; then
    . "${SUITE_DIR}/test.sh"
else
    echo "error: test.sh not found in ${SUITE_DIR}"
    exit 1
fi

# --- Main Script Execution ---

# Trap EXIT signal to call cleanup function
# Pass error code, line number, and command to the cleanup function
trap 'cleanup_resources $? $LINENO "$BASH_COMMAND"' EXIT

check_env_vars "$@" # Pass all args for consistency, though check_env_vars doesn't use them
parse_options "$@" # Parses options and sets CLEANUP, NO_CVE

decrypt_secrets
create_github_repository
patch_component_source
setup_namespaces # Ensures correct context before resource creation
cleanup_old_resources "${originating_tool}"
create_kubernetes_resources # tmpDir is set here

wait_for_component_initialization # component_pr and pr_number are set here
patch_component_source_before_merge
merge_github_pr # SHA is set here

wait_for_plr_to_appear # component_push_plr_name is set here
wait_for_plr_to_complete

wait_for_releases # RELEASE_NAME, RELEASE_NAMESPACE are set and exported here
verify_release_contents

echo "✅️ End-to-end test script completed successfully."
exit 0
