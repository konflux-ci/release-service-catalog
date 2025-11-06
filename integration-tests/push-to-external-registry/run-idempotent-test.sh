#!/usr/bin/env bash
#
# run-idempotent-test.sh - Custom test runner for idempotent release testing
#
# Overview:
#   This script validates idempotent release behavior by creating two releases
#   with the same snapshot and verifying that the second release correctly
#   filters already-released components.
#
#   Unlike standard run-test.sh which creates one release, this script:
#     1. Creates initial release (Release-1) - components are pushed
#     2. Waits for completion and verifies artifacts
#     3. Creates second release with SAME snapshot (Release-2)
#     4. Verifies Release-2 filtered all components (idempotency validated)
#
# Usage:
#   ./run-idempotent-test.sh [options]
#
# Options:
#   -sc, --skip-cleanup   : Skip cleanup operations on exit
#   -nocve, --no-cve      : Do not simulate CVE addition
#
# Exit Behavior:
#   - Exits 0 on successful completion of all steps and verifications.
#   - Exits with a non-zero status code on error.
#   - A trap is set to call 'cleanup_resources' on EXIT.
#

set -eo pipefail

# --- Configuration & Global Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="${SCRIPT_DIR}"
export SUITE_DIR

# Source the function library FIRST
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/test-functions.sh"

echo "════════════════════════════════════════════════════════════════════"
echo "  E2E Test: Idempotent Release Behavior"
echo "  Testing: push-to-external-registry pipeline"
echo "════════════════════════════════════════════════════════════════════"
echo ""

parse_options "$@"

# Load configuration AFTER parse_options
# shellcheck disable=SC1091
source "${SUITE_DIR}/test.env"

check_env_vars

# Source test-specific helper functions
# shellcheck disable=SC1091
source "${SUITE_DIR}/idempotent-test-functions.sh"

# Trap EXIT signal to call cleanup function
trap 'cleanup_resources $? $LINENO "$BASH_COMMAND"' EXIT

# Generate unique UUID for this test run (overrides the one from test.env)
# MUST be done BEFORE create_kubernetes_resources so secrets have correct names!
uuid=$(openssl rand -hex 4)
uuid="${uuid:0:8}"
echo "Test UUID: ${uuid}"

# Update names with UUID
export application_name="e2eapp-idempotent-${uuid}"
export component_name="comp-idempotent-${uuid}"
export component_branch="branch-${uuid}"
export release_plan_name="rp-idempotent-${uuid}"
export release_plan_admission_name="rpa-idempotent-${uuid}"
export managed_sa_name="sa-idempotent-${uuid}"
export component_repo_name="${component_github_org}/${component_name}"
export component_git_url="https://github.com/${component_repo_name}"

RELEASE_1_NAME="release-idempotent-1-${uuid}"
RELEASE_2_NAME="release-idempotent-2-${uuid}"

echo ""
echo "Test Configuration:"
echo "  Application: ${application_name}"
echo "  Component: ${component_name}"
echo "  Release 1: ${RELEASE_1_NAME}"
echo "  Release 2: ${RELEASE_2_NAME}"
echo "  Tenant Namespace: ${tenant_namespace}"
echo "  Managed Namespace: ${managed_namespace}"
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "PHASE 1: Setting up test environment"
echo "════════════════════════════════════════════════════════════════════"

echo "Decrypting secrets..."
decrypt_secrets "${SUITE_DIR}"

echo "Creating Kubernetes resources..."
create_kubernetes_resources

echo "Creating GitHub repository..."
create_github_repository

echo "Setting up namespace context..."
setup_namespaces

echo "✅ Setup complete"
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "PHASE 2: First Release (Initial)"
echo "════════════════════════════════════════════════════════════════════"

echo "Waiting for snapshot to be created..."
wait_for_component_initialization

merge_github_pr

wait_for_plr_to_appear "${application_name}" "${component_name}" "${tenant_namespace}"
wait_for_plr_to_complete

# Get the snapshot that was created (wait up to 12 minutes for it to appear)
echo "Waiting for snapshot to appear..."
SNAPSHOT_NAME=""
max_attempts=72  # 12 minutes with 10-second intervals
attempt=1

while [ $attempt -le $max_attempts ] && [ -z "$SNAPSHOT_NAME" ]; do
    SNAPSHOT_NAME=$(kubectl get snapshots -n "${tenant_namespace}" \
        --sort-by=.metadata.creationTimestamp \
        -l appstudio.openshift.io/application="${application_name}" \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)
    
    if [ -n "${SNAPSHOT_NAME}" ]; then
        echo "✅ Found snapshot: ${SNAPSHOT_NAME}"
        break
    fi
    
    echo "  Attempt $attempt/$max_attempts: No snapshot found yet, waiting 10 seconds..."
    sleep 10
    attempt=$((attempt + 1))
done

if [ -z "${SNAPSHOT_NAME}" ]; then
    echo "❌ ERROR: No snapshot found after waiting $((max_attempts * 10)) seconds"
    echo "Available snapshots in namespace ${tenant_namespace}:"
    kubectl get snapshots -n "${tenant_namespace}" \
        -l appstudio.openshift.io/application="${application_name}" \
        -o wide 2>/dev/null || echo "  (none found)"
    exit 1
fi

echo "Using snapshot: ${SNAPSHOT_NAME}"
echo ""

echo "Creating first release..."
RELEASE_1_START=$(date +%s)

cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${RELEASE_1_NAME}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-type: "idempotent-first-release"
spec:
  snapshot: ${SNAPSHOT_NAME}
  releasePlan: ${release_plan_name}
EOF

echo "Waiting for Release-1 to complete..."
wait_for_release "${RELEASE_1_NAME}" "${tenant_namespace}"

RELEASE_1_END=$(date +%s)
RELEASE_1_DURATION=$((RELEASE_1_END - RELEASE_1_START))

echo ""
echo "✅ Release-1 completed in ${RELEASE_1_DURATION}s"

echo "Checking if all components were filtered..."
if were_all_components_filtered "${RELEASE_1_NAME}"; then
    FILTERED_COUNT_1=1
    echo "  - All components filtered: YES"
else
    FILTERED_COUNT_1=0
    echo "  - All components filtered: NO"
fi
echo ""

echo "Verifying Release-1 contents..."
RELEASE_NAME="${RELEASE_1_NAME}"
RELEASE_NAMESPACE="${tenant_namespace}"
verify_release_contents

echo ""
echo "Checking first release expectations..."

if [ "${FILTERED_COUNT_1}" -ne 0 ]; then
    log_error "Expected filteredCount=0 on first release, got ${FILTERED_COUNT_1}"
fi

echo "✅ First release validated:"
echo "   - Components pushed to registry"
echo "   - No components filtered (expected behavior)"
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "PHASE 3: Second Release (Idempotent Retry)"
echo "════════════════════════════════════════════════════════════════════"

echo "Creating second release with SAME snapshot..."
RELEASE_2_START=$(date +%s)

cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${RELEASE_2_NAME}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-type: "idempotent-second-release"
spec:
  snapshot: ${SNAPSHOT_NAME}
  releasePlan: ${release_plan_name}
EOF

echo "Waiting for Release-2 to complete..."
wait_for_release "${RELEASE_2_NAME}" "${tenant_namespace}"

RELEASE_2_END=$(date +%s)
RELEASE_2_DURATION=$((RELEASE_2_END - RELEASE_2_START))

echo ""
echo "✅ Release-2 completed in ${RELEASE_2_DURATION}s"

echo "Checking if all components were filtered..."
if were_all_components_filtered "${RELEASE_2_NAME}"; then
    FILTERED_COUNT_2=1
    echo "  - All components filtered: YES"
else
    FILTERED_COUNT_2=0
    echo "  - All components filtered: NO"
fi
echo ""

EXPECTED_FILTERED=1  # We have 1 component
if [ "${FILTERED_COUNT_2}" -ne "${EXPECTED_FILTERED}" ]; then
    log_error "Expected filteredCount=${EXPECTED_FILTERED} on second release, got ${FILTERED_COUNT_2}"
fi

echo "✅ Second release validated:"
echo "   - ${FILTERED_COUNT_2} component(s) filtered (already released)"
echo "   - Idempotent behavior confirmed"
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "PHASE 4: Comprehensive Verification"
echo "════════════════════════════════════════════════════════════════════"

echo "1. Verifying registry state (no duplicates)..."
RELEASE_NAME="${RELEASE_2_NAME}"
RELEASE_NAMESPACE="${tenant_namespace}"
verify_release_contents
echo "✅ Registry check passed (no duplicate images)"
echo ""

echo "2. Performance Comparison:"
echo "   Release-1 (initial):    ${RELEASE_1_DURATION}s"
echo "   Release-2 (idempotent): ${RELEASE_2_DURATION}s"

if [ "${RELEASE_2_DURATION}" -lt "${RELEASE_1_DURATION}" ]; then
    SAVINGS=$((RELEASE_1_DURATION - RELEASE_2_DURATION))
    PERCENT=$(( (SAVINGS * 100) / RELEASE_1_DURATION ))
    echo "   ✅ Idempotent release was ${SAVINGS}s faster (${PERCENT}% improvement)!"
else
    echo "   ⚠️  Idempotent release not significantly faster (may be within variance)"
fi
echo ""

echo "3. Verifying EC validation behavior..."
if is_taskrun_skipped "${RELEASE_2_NAME}" "verify-enterprise-contract"; then
    echo "✅ EC validation was skipped (optimal - empty snapshot)"
else
    echo "⚠️  EC validation ran (expected if using minimal snapshot approach)"
    # This is not necessarily an error - EC might run but with empty/minimal snapshot
fi
echo ""

echo "4. Verifying artifact consistency..."
RELEASE_1_JSON=$(get_release_json "${RELEASE_1_NAME}")
RELEASE_2_JSON=$(get_release_json "${RELEASE_2_NAME}")

ARTIFACTS_1=$(jq -S '.status.artifacts.images[0].shasum' <<< "${RELEASE_1_JSON}")
ARTIFACTS_2=$(jq -S '.status.artifacts.images[0].shasum' <<< "${RELEASE_2_JSON}")

# Release-2 may have no artifacts if all components were filtered
if [ "${FILTERED_COUNT_2}" -eq "${EXPECTED_FILTERED}" ] && [ "${ARTIFACTS_2}" == "null" ]; then
    echo "✅ Release-2 has no artifacts (expected - all components were filtered, push-snapshot was skipped)"
    echo "   Release-1 pushed: ${ARTIFACTS_1}"
    echo "   Release-2 skipped push (idempotent)"
elif [ "${ARTIFACTS_1}" == "${ARTIFACTS_2}" ]; then
    echo "✅ Both releases report identical artifact digests"
else
    echo "Release-1 artifacts: ${ARTIFACTS_1}"
    echo "Release-2 artifacts: ${ARTIFACTS_2}"
    log_error "Releases report different artifacts: ${ARTIFACTS_1} vs ${ARTIFACTS_2}"
fi
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "  ✅ E2E IDEMPOTENT TEST PASSED"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • First release pushed 1 component"
echo "  • Second release filtered ${FILTERED_COUNT_2} component(s)"
echo "  • No duplicate images in registry"
echo "  • Performance: ${RELEASE_1_DURATION}s → ${RELEASE_2_DURATION}s"
echo "  • Artifact consistency: Verified"
echo "  • Idempotent behavior: ✅ CONFIRMED"
echo ""
echo "════════════════════════════════════════════════════════════════════"

echo ""
echo "✅ End-to-end idempotent test completed successfully."
exit 0

