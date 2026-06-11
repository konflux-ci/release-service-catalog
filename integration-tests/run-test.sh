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
#   CI: changes to this file select the full release-pipelines e2e matrix
#   (see integration-tests/scripts/find_release_pipelines_from_pr.sh).
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
#   -i, --interactive     : Enable interactive mode. On failure, pauses and offers:
#                           [r] Retry with same snapshot (no RPM rebuild needed)
#                           [i] Show release context info
#                           [s] Drop into shell for debugging
#                           [c] Cleanup and exit
#                           [q] Quit without cleanup
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

# --- Configuration & Global Variables ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LIB_DIR="${SCRIPT_DIR}/lib"

# Parse arguments - extract suite name (first non-option argument)
suite=""
args=()
for arg in "$@"; do
  case "$arg" in
    -sc|--skip-cleanup|-nocve|--no-cve|-i|--interactive)
      args+=("$arg")
      ;;
    -*)
      echo "🔴 error: unknown option: $arg"
      echo "Usage: ./run-test.sh <suite_name> [options]"
      echo "Options: -i/--interactive, -sc/--skip-cleanup, -nocve/--no-cve"
      exit 1
      ;;
    *)
      if [ -z "$suite" ]; then
        suite="$arg"
      else
        echo "🔴 error: unexpected argument: $arg"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$suite" ]; then
  echo "🔴 error: missing parameter suite"
  echo "Usage: ./run-test.sh <suite_name> [options]"
  echo "Example: ./run-test.sh push-rpms-to-pulp -i"
  exit 1
fi

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

PTSV_BUILD_PIPELINE=""
PTSV_BUILD_PIPELINE_BUNDLE="latest"
if [ -z "$PTSV_COMPONENTS" ]; then
    PTSV_COMPONENTS="component"
fi

if [[ -n "${PIPELINE_TEST_SUITE_VARS:-}" ]] && jq -e . >/dev/null 2>&1 <<<"${PIPELINE_TEST_SUITE_VARS}"; then
    # Only allow PTSV_* keys from the JSON object
    source <(
        jq -r 'to_entries[]
               | select(.key | startswith("PTSV_"))
               | "export \(.key)=\(.value|@sh)"' <<<"${PIPELINE_TEST_SUITE_VARS}"
    )
fi

# If custom pipeline is specified, set annotation variable for later use in component patching
if [[ -n "${PTSV_BUILD_PIPELINE}" ]]; then
    export PTSV_BUILD_PIPELINE_VALUE=$(
        printf '{"name": "%s", "bundle": "%s"}' "${PTSV_BUILD_PIPELINE}" "${PTSV_BUILD_PIPELINE_BUNDLE}"
    )
fi

# --- Main Script Execution ---

# Trap EXIT signal to call cleanup function
# Pass error code, line number, and command to the cleanup function
trap 'cleanup_resources $? $LINENO "$BASH_COMMAND"' EXIT

check_env_vars "${args[@]}" # Pass all args for consistency, though check_env_vars doesn't use them
parse_options "${args[@]}" # Parses options and sets CLEANUP, NO_CVE, INTERACTIVE_MODE

decrypt_secrets "${SUITE_DIR}"
create_github_repositories
patch_components_source
setup_namespaces # Ensures correct context before resource creation
cleanup_old_resources "${originating_tool}"
create_kubernetes_resources # tmpDir is set here

# Call post_create_kubernetes_resources hook if defined (for test-specific setup)
if type post_create_kubernetes_resources &>/dev/null; then
    post_create_kubernetes_resources
fi

wait_for_components_initialization # component_pr and pr_number are set here
patch_components_source_before_merge
merge_github_prs # SHA is set here

wait_for_plrs_to_appear
wait_for_plrs_to_complete

wait_for_releases # RELEASE_NAME, RELEASE_NAMESPACE are set and exported here
verify_release_contents

echo "✅️ End-to-end test script completed successfully."
exit 0
