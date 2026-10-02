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
#     KUBECONFIG                    - Optional path to kubeconfig for local runs.
#                                     Konflux ITS use in-cluster auth (unset).
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
#       (e.g., delete-single-branch.sh, wait-for-release.sh,
#        get-advisory-content.sh, etc.).
#
# Exit Behavior:
#   - Exits 0 on successful completion of all steps and verifications.
#   - Exits with a non-zero status code on error.
#   - A trap is set to call the 'cleanup_resources' function on EXIT,
#     regardless of success or failure (unless --skip-cleanup is used).
#     The cleanup function receives the exit code, line number, and command.
#


set -Eeo pipefail

# --- Configuration & Global Variables ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LIB_DIR="${SCRIPT_DIR}/lib"
if [ -z "${RUN_TEST_METADATA_FILE:-}" ]; then
    RUN_TEST_METADATA_FILE=$(mktemp /tmp/run-test-metadata.XXXXXX.json)
fi
CURRENT_STAGE="setup"
CURRENT_TASK="startup"
FAILURE_METADATA_CAPTURED="false"
FAILURE_METADATA_ENABLED="false"
RUN_TEST_FAILURE_MESSAGE=""
RUN_TEST_METADATA_WRITTEN="false"

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

if [ -z "$PTSV_EXPECTED_ARCHES" ]; then
    PTSV_EXPECTED_ARCHES="amd64"
fi

reset_failure_context() {
    DETECTED_STAGE=""
    DETECTED_TASK=""
    DETECTED_MESSAGE=""
    DETECTED_PLR_URL=""
}

run_test_metadata_key() {
    local metadata_key="${RUN_TEST_METADATA_KEY:-${suite}}"
    local metadata_vars metadata_hash

    # Distinguish ITS variants that reuse the same suite but carry different vars.
    if [ -n "${RUN_TEST_METADATA_KEY:-}" ]; then
        printf '%s' "${metadata_key}"
        return 0
    fi

    if [[ -n "${PIPELINE_TEST_SUITE_VARS:-}" ]] && jq -e . >/dev/null 2>&1 <<<"${PIPELINE_TEST_SUITE_VARS}"; then
        metadata_vars="$(jq -cS . <<<"${PIPELINE_TEST_SUITE_VARS}")"
        if [ "${metadata_vars}" != "{}" ] && [ "${metadata_vars}" != "null" ]; then
            metadata_hash="$(printf '%s' "${metadata_vars}" | sha256sum | cut -d' ' -f1)"
            metadata_key="${suite}:${metadata_hash}"
        fi
    fi

    printf '%s' "${metadata_key}"
}

set_current_step() {
    CURRENT_STAGE="$1"
    CURRENT_TASK="$2"
    RUN_TEST_FAILURE_MESSAGE=""
}

current_task_failure_label() {
    case "${CURRENT_TASK}" in
        create_github_repositories)
            echo "repository setup"
            ;;
        patch_components_source|patch_components_source_before_merge)
            echo "component source setup"
            ;;
        setup_namespaces|create_kubernetes_resources|post_create_kubernetes_resources)
            echo "release test setup"
            ;;
        cleanup_old_resources)
            echo "cleanup old resources"
            ;;
        wait_for_components_initialization)
            echo "component initialization"
            ;;
        merge_github_prs)
            echo "pull request merge"
            ;;
        wait_for_plrs_to_appear|wait_for_plrs_to_complete)
            echo "component build pipeline"
            ;;
        wait_for_releases)
            echo "release processing"
            ;;
        verify_release_contents)
            echo "post-release checks"
            ;;
        *)
            echo "${CURRENT_TASK}"
            ;;
    esac
}

is_noisy_failed_command() {
    local failed_command="${1:-}"

    [ -z "${failed_command}" ] && return 0
    [ "${failed_command}" = "exit 1" ] && return 0
    [[ "${failed_command}" == return* ]] && return 0
    [[ "${failed_command}" == *"/run-test.sh"* ]] && return 0
    return 1
}

write_run_test_metadata() {
    local result="$1"

    jq -nc \
        --arg its_key "$(run_test_metadata_key)" \
        --arg its_name "${suite}" \
        --arg result "${result}" \
        --arg failure_label "${DETECTED_TASK}" \
        --arg details_url "${DETECTED_PLR_URL}" \
        --arg details_text "${DETECTED_MESSAGE}" \
        '{
            its_key: $its_key,
            its_name: $its_name,
            result: $result,
            failure_label: $failure_label,
            details_url: $details_url,
            details_text: $details_text
        }' > "${RUN_TEST_METADATA_FILE}"
    RUN_TEST_METADATA_WRITTEN="true"
}

set_pipelinerun_failure_context() {
    local stage="$1"
    local plr_name="$2"
    local namespace="$3"
    local fallback_task="$4"
    local include_taskrun_message="${5:-true}"
    local taskrun_json task_name task_message pipelinerun_json condition_reason

    taskrun_json=$(kubectl get taskruns -n "${namespace}" \
        -l "tekton.dev/pipelineRun=${plr_name}" -o json 2>/dev/null || true)
    task_name=$(jq -r '
        first(
            .items[]?
            | select((.status.conditions[0].status // "") == "False")
            | (.metadata.labels["tekton.dev/pipelineTask"] // .metadata.name)
        ) // ""' <<< "${taskrun_json}")
    task_message=$(jq -r '
        first(
            .items[]?
            | select((.status.conditions[0].status // "") == "False")
            | (.status.conditions[0].message // "")
        ) // ""' <<< "${taskrun_json}")

    if [ -z "${task_name}" ]; then
        pipelinerun_json=$(kubectl get pipelinerun "${plr_name}" -n "${namespace}" \
            -o json 2>/dev/null || true)
        condition_reason=$(jq -r '
            first(.status.conditions[]? | select(.type == "Succeeded") | .reason) // ""' \
            <<< "${pipelinerun_json}")
        task_message=$(jq -r '
            first(.status.conditions[]? | select(.type == "Succeeded") | .message) // ""' \
            <<< "${pipelinerun_json}")
        if [ -n "${condition_reason}" ] && [ -n "${task_message}" ]; then
            task_message="${condition_reason}: ${task_message}"
        elif [ -n "${condition_reason}" ]; then
            task_message="PipelineRun reason: ${condition_reason}"
        fi
    fi

    DETECTED_STAGE="${stage}"
    DETECTED_TASK="${task_name:-${fallback_task:-${CURRENT_TASK}}}"
    if [ -n "${task_name}" ] && [ "${include_taskrun_message}" != "true" ]; then
        DETECTED_MESSAGE=""
    else
        DETECTED_MESSAGE="${task_message}"
    fi
    if type get_pipelinerun_console_url &>/dev/null; then
        DETECTED_PLR_URL=$(get_pipelinerun_console_url "${namespace}" "${plr_name}")
    fi
}

capture_build_failure_context() {
    local component
    local plr_name_var plr_name completed

    for component in ${PTSV_COMPONENTS}; do
        plr_name_var="${component}_push_plr_name"
        plr_name="${!plr_name_var}"
        [ -z "${plr_name}" ] && continue

        completed=$(kubectl get pipelinerun "${plr_name}" -n "${tenant_namespace}" \
            -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' \
            2>/dev/null || true)
        if [ "${completed}" != "False" ]; then
            continue
        fi

        set_pipelinerun_failure_context \
            "component-build" \
            "${plr_name}" \
            "${tenant_namespace}" \
            "component build pipeline"
        return 0
    done

    return 1
}

release_condition_failed() {
    local release_json="$1"
    local condition_type="$2"

    jq -e --arg condition_type "${condition_type}" '
        any(
            .status.conditions[]?;
            .type == $condition_type and .status == "False"
        )' <<< "${release_json}" >/dev/null 2>&1
}

capture_release_section_context() {
    local release_json="$1"
    local stage="$2"
    local condition_type="$3"
    local pipeline_filter="$4"
    local pipeline_run namespace plr_name condition_message fallback_task

    if ! release_condition_failed "${release_json}" "${condition_type}"; then
        return 1
    fi

    fallback_task="${condition_type}"
    pipeline_run=$(jq -r "${pipeline_filter} // \"\"" <<< "${release_json}")
    condition_message=$(jq -r --arg condition_type "${condition_type}" '
        first(
            .status.conditions[]?
            | select(.type == $condition_type and .status == "False")
            | .message
        ) // ""' <<< "${release_json}")

    if [ -z "${pipeline_run}" ]; then
        DETECTED_STAGE="${stage}"
        DETECTED_TASK="${fallback_task}"
        DETECTED_MESSAGE="${condition_message}"
        return 0
    fi

    namespace="${pipeline_run%%/*}"
    plr_name="${pipeline_run##*/}"
    set_pipelinerun_failure_context \
        "${stage}" \
        "${plr_name}" \
        "${namespace}" \
        "${fallback_task}" \
        "false"
    # Prefer the failed TaskRun message when we have it. The Release condition
    # message is usually broader and can hide the specific failing task/step.
    if [ "${DETECTED_TASK}" = "${fallback_task}" ] && [ -z "${DETECTED_MESSAGE}" ] && [ -n "${condition_message}" ]; then
        DETECTED_MESSAGE="${condition_message}"
    fi
    return 0
}

capture_release_failure_context() {
    local release_name release_namespace release_json
    local release_names="${FAILED_RELEASE_NAMES:-${RELEASE_NAMES:-${RELEASE_NAME:-}}}"

    for release_name in ${release_names}; do
        [ -z "${release_name}" ] && continue
        release_namespace="${RELEASE_NAMESPACE:-${tenant_namespace}}"
        release_json=$(kubectl get release "${release_name}" -n "${release_namespace}" \
            -o json 2>/dev/null || true)
        [ -z "${release_json}" ] && continue

        if capture_release_section_context \
            "${release_json}" \
            "release-processing" \
            "TenantCollectorsPipelineProcessed" \
            '.status.collectorsProcessing.tenantCollectorsProcessing.pipelineRun'; then
            return 0
        fi

        if capture_release_section_context \
            "${release_json}" \
            "release-processing" \
            "ManagedCollectorsPipelineProcessed" \
            '.status.collectorsProcessing.managedCollectorsProcessing.pipelineRun'; then
            return 0
        fi

        if capture_release_section_context \
            "${release_json}" \
            "release-processing" \
            "TenantPipelineProcessed" \
            '.status.tenantProcessing.pipelineRun'; then
            return 0
        fi

        if capture_release_section_context \
            "${release_json}" \
            "release-processing" \
            "ManagedPipelineProcessed" \
            '.status.managedProcessing.pipelineRun'; then
            return 0
        fi

        if capture_release_section_context \
            "${release_json}" \
            "post-release-checks" \
            "FinalPipelineProcessed" \
            '.status.finalProcessing.pipelineRun'; then
            return 0
        fi
    done

    return 1
}

capture_post_release_checks_context() {
    local release_name release_namespace release_json pipeline_run namespace plr_name
    local release_names="${FAILED_RELEASE_NAMES:-${RELEASE_NAMES:-${RELEASE_NAME:-}}}"
    local saw_release="false"

    for release_name in ${release_names}; do
        [ -z "${release_name}" ] && continue
        release_namespace="${RELEASE_NAMESPACE:-${tenant_namespace}}"
        release_json=$(kubectl get release "${release_name}" -n "${release_namespace}" \
            -o json 2>/dev/null || true)
        [ -z "${release_json}" ] && continue
        saw_release="true"

        pipeline_run=$(jq -r '
            .status.finalProcessing.pipelineRun
            // .status.managedProcessing.pipelineRun
            // ""' <<< "${release_json}")

        if [ -z "${pipeline_run}" ]; then
            continue
        fi

        DETECTED_STAGE="post-release-checks"
        DETECTED_TASK="post-release checks"
        namespace="${pipeline_run%%/*}"
        plr_name="${pipeline_run##*/}"
        if type get_pipelinerun_console_url &>/dev/null; then
            DETECTED_PLR_URL=$(get_pipelinerun_console_url "${namespace}" "${plr_name}")
        fi
        return 0
    done

    if [ "${saw_release}" = "true" ]; then
        DETECTED_STAGE="post-release-checks"
        DETECTED_TASK="post-release checks"
        return 0
    fi

    return 1
}

capture_failure_context() {
    local failed_command="${1:-}"

    reset_failure_context

    if [ "${CURRENT_TASK}" = "verify_release_contents" ]; then
        capture_post_release_checks_context || true
    fi

    if [ -z "${DETECTED_TASK}" ]; then
        capture_release_failure_context || true
    fi

    if [ -z "${DETECTED_TASK}" ]; then
        capture_build_failure_context || true
    fi

    if [ -z "${DETECTED_TASK}" ]; then
        DETECTED_STAGE="${CURRENT_STAGE}"
        DETECTED_TASK=$(current_task_failure_label)
    fi

    if [ -z "${DETECTED_MESSAGE}" ]; then
        if [ -n "${RUN_TEST_FAILURE_MESSAGE}" ]; then
            DETECTED_MESSAGE="${RUN_TEST_FAILURE_MESSAGE}"
            return 0
        fi
        if [ -n "${failed_command}" ] && ! is_noisy_failed_command "${failed_command}"; then
            DETECTED_MESSAGE="command failed during ${DETECTED_TASK}: ${failed_command}"
        else
            DETECTED_MESSAGE="${DETECTED_TASK} failed"
        fi
    fi
}

save_failure_metadata() {
    local exit_code="$1"
    local failed_line="$2"
    local failed_command="$3"
    local action="${4:-Captured}"
    local had_errexit="false"

    if [ "${FAILURE_METADATA_ENABLED}" != "true" ]; then
        return 0
    fi

    if [[ "$-" == *e* ]]; then
        had_errexit="true"
    fi

    set +e
    capture_failure_context "${failed_command}"
    write_run_test_metadata "FAILURE"
    echo "${action} failure metadata in ${RUN_TEST_METADATA_FILE} (exit ${exit_code}, line ${failed_line})"
    if [ "${had_errexit}" = "true" ]; then
        set -e
    fi
}

record_failure_metadata() {
    local exit_code="$1"
    local failed_line="$2"
    local failed_command="$3"

    if [ "${FAILURE_METADATA_CAPTURED}" = "true" ]; then
        return 0
    fi
    FAILURE_METADATA_CAPTURED="true"
    save_failure_metadata "${exit_code}" "${failed_line}" "${failed_command}" "Captured"
}

refresh_failure_metadata() {
    local exit_code="$1"
    local failed_line="$2"
    local failed_command="$3"

    FAILURE_METADATA_CAPTURED="true"
    save_failure_metadata "${exit_code}" "${failed_line}" "${failed_command}" "Updated"
}

print_run_test_summary() {
    local result its_name failure_label details_url details_text

    [ "${RUN_TEST_METADATA_WRITTEN}" = "true" ] || return 0
    [ -f "${RUN_TEST_METADATA_FILE}" ] || return 0

    result=$(jq -r '.result // ""' < "${RUN_TEST_METADATA_FILE}")
    its_name=$(jq -r '.its_name // ""' < "${RUN_TEST_METADATA_FILE}")
    failure_label=$(jq -r '.failure_label // ""' < "${RUN_TEST_METADATA_FILE}")
    details_url=$(jq -r '.details_url // ""' < "${RUN_TEST_METADATA_FILE}")
    details_text=$(jq -r '.details_text // ""' < "${RUN_TEST_METADATA_FILE}")

    echo ""
    echo "=== run-test summary ==="
    if [ "${result}" = "SUCCESS" ]; then
        echo "result: SUCCESS"
        echo "test: ${its_name}"
        return 0
    fi

    if [ -z "${failure_label}" ]; then
        failure_label=$(current_task_failure_label)
    fi

    echo "result: FAILURE"
    echo "test: ${its_name}"
    echo "failure: ${failure_label}"

    if [ -n "${details_url}" ]; then
        echo "link: ${details_url}"
    fi

    if [ -n "${details_text}" ]; then
        echo "details: ${details_text}"
    fi
}

finalize_run() {
    local exit_code="$1"
    local failed_line="$2"
    local failed_command="$3"
    local cleanup_status
    local final_status="${exit_code}"
    local had_errexit="false"

    trap - ERR EXIT

    if [ "${exit_code}" -ne 0 ]; then
        # The final non-zero exit is authoritative. This avoids stale metadata
        # from earlier retryable failures within the same run.
        refresh_failure_metadata "${exit_code}" "${failed_line}" "${failed_command}"
    fi

    if [[ "$-" == *e* ]]; then
        had_errexit="true"
    fi

    set +e
    cleanup_resources "${exit_code}" "${failed_line}" "${failed_command}"
    cleanup_status=$?
    if [ "${had_errexit}" = "true" ]; then
        set -e
    fi

    if [ "${cleanup_status}" -ne 0 ]; then
        echo "Warning: cleanup exited with status ${cleanup_status}, preserving test result"
    fi

    print_run_test_summary
    exit "${final_status}"
}

# --- Main Script Execution ---

# Capture failure details before the EXIT trap performs cleanup.
trap 'record_failure_metadata $? $LINENO "$BASH_COMMAND"' ERR

# Trap EXIT signal to call cleanup function
# Pass error code, line number, and command to the cleanup function
trap 'finalize_run $? $LINENO "$BASH_COMMAND"' EXIT

reset_failure_context
check_env_vars "${args[@]}" # Pass all args for consistency, though check_env_vars doesn't use them
parse_options "${args[@]}" # Parses options and sets CLEANUP, NO_CVE, INTERACTIVE_MODE

decrypt_secrets "${SUITE_DIR}"
FAILURE_METADATA_ENABLED="true"
write_run_test_metadata "RUNNING"

set_current_step "setup" "create_github_repositories"
create_github_repositories
set_current_step "setup" "patch_components_source"
patch_components_source
set_current_step "setup" "setup_namespaces"
setup_namespaces # Ensures correct context before resource creation
set_current_step "setup" "cleanup_old_resources"
cleanup_old_resources "${originating_tool}"
set_current_step "setup" "create_kubernetes_resources"
create_kubernetes_resources # tmpDir is set here

# Call post_create_kubernetes_resources hook if defined (for test-specific setup)
if type post_create_kubernetes_resources &>/dev/null; then
    set_current_step "setup" "post_create_kubernetes_resources"
    post_create_kubernetes_resources
fi

set_current_step "component-build" "wait_for_components_initialization"
wait_for_components_initialization # component_pr and pr_number are set here
set_current_step "component-build" "patch_components_source_before_merge"
patch_components_source_before_merge
set_current_step "component-build" "merge_github_prs"
merge_github_prs # SHA is set here

set_current_step "component-build" "wait_for_plrs_to_appear"
wait_for_plrs_to_appear
set_current_step "component-build" "wait_for_plrs_to_complete"
wait_for_plrs_to_complete

set_current_step "release-processing" "wait_for_releases"
wait_for_releases # RELEASE_NAME, RELEASE_NAMESPACE are set and exported here
set_current_step "post-release-checks" "verify_release_contents"
verify_release_contents

reset_failure_context
write_run_test_metadata "SUCCESS"
echo "✅️ End-to-end test script completed successfully."
exit 0
