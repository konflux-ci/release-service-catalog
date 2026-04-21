#!/usr/bin/env bash
#
# test.sh - Test-specific functions for push-to-external-registry-idempotent
#
# This test validates idempotent release behavior by:
#   1. Verifying the first (auto-created) release pushed components
#   2. Creating a second release with the SAME snapshot
#   3. Verifying the second release filtered all components (idempotency)
#
# This file is sourced by run-test.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Check if all components were filtered (idempotency validation)
# Returns 0 (true) if push-snapshot task was skipped, 1 (false) otherwise
were_all_components_filtered() {
    local release_name=$1

    # Check if all components were filtered by seeing if push-snapshot was skipped
    is_task_skipped "${release_name}" "push-snapshot"
}

# Verify a single release has valid artifacts and image can be pulled
verify_single_release() {
    local release_name=$1
    echo "Verifying Release contents for ${release_name}..."

    local release_json
    release_json=$(get_release_json "${release_name}")
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi

    local failures=0
    local image_url image_arch image_shasum

    image_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image_arch=$(jq -r '.status.artifacts.images[0]?.arches[0] // ""' <<< "${release_json}")
    image_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")

    echo "Checking Image URL..."
    if [ -n "${image_url}" ]; then
        echo "✅️ image_url: ${image_url}"
    else
        echo "🔴 image_url was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Arch..."
    if [ -n "${image_arch}" ]; then
        echo "✅️ image_arch: ${image_arch}"
    else
        echo "🔴 image_arch was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Shasum..."
    if [ -n "${image_shasum}" ]; then
        echo "✅️ image_shasum: ${image_shasum}"
    else
        echo "🔴 image_shasum was empty"
        failures=$((failures+1))
    fi

    echo "Verifying image pullability with skopeo..."
    set +e
    "${SUITE_DIR}/../scripts/skopeo-verify-image.sh" \
        "${image_url}" "${image_shasum}" \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"
    skopeo_return_code=$?
    set -e
    if [ "${skopeo_return_code}" -ne 0 ]; then
        failures=$((failures+1))
    fi

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Release verification FAILED with ${failures} failure(s)!"
        return 1
    else
        echo "✅️ All release checks passed."
        return 0
    fi
}

# Function to verify Release contents - called by run-test.sh after first release completes
# This function implements the idempotent test logic:
#   1. Verify first release pushed components
#   2. Create second release with same snapshot
#   3. Verify second release filtered all components
verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 1: First Release Verification"
    echo "════════════════════════════════════════════════════════════════════"

    # RELEASE_NAMES is set by wait_for_releases in run-test.sh
    local first_release_name
    first_release_name=$(echo "${RELEASE_NAMES}" | awk '{print $1}')

    echo "First release: ${first_release_name}"

    # Verify first release was NOT filtered (components should be pushed)
    echo "Checking if first release pushed components..."
    if were_all_components_filtered "${first_release_name}"; then
        log_error "First release should NOT have filtered components, but push-snapshot was skipped"
    fi
    echo "✅ First release pushed components (expected behavior)"

    # Verify first release artifacts
    if ! verify_single_release "${first_release_name}"; then
        log_error "First release verification failed"
    fi

    # Get the snapshot from the first release for the second release
    local first_release_json
    first_release_json=$(get_release_json "${first_release_name}")
    local snapshot_name
    snapshot_name=$(jq -r '.spec.snapshot' <<< "${first_release_json}")

    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Using snapshot: ${snapshot_name}"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 2: Second Release (Idempotent)"
    echo "════════════════════════════════════════════════════════════════════"

    # Create second release with the SAME snapshot
    local second_release_name="idempotent-retry-${uuid}"
    echo "Creating second release: ${second_release_name}"

    cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${second_release_name}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-type: "idempotent-second-release"
spec:
  snapshot: ${snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    # Wait for second release to complete
    echo "Waiting for second release to complete..."
    export RELEASE_NAME="${second_release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    "${SUITE_DIR}/../scripts/wait-for-release.sh"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 3: Idempotent Behavior Verification"
    echo "════════════════════════════════════════════════════════════════════"

    # Verify second release filtered all components (idempotent behavior)
    echo "Checking if second release filtered all components..."
    if were_all_components_filtered "${second_release_name}"; then
        echo "✅ Second release filtered all components (idempotent behavior confirmed)"
    else
        log_error "Second release should have filtered all components, but push-snapshot ran"
    fi

    # Verify artifact consistency
    echo ""
    echo "Verifying artifact consistency..."
    local second_release_json
    second_release_json=$(get_release_json "${second_release_name}")

    local artifacts_1 artifacts_2
    artifacts_1=$(jq -S '.status.artifacts.images[0].shasum // "null"' <<< "${first_release_json}")
    artifacts_2=$(jq -S '.status.artifacts.images[0].shasum // "null"' <<< "${second_release_json}")

    # Second release may have no artifacts if all components were filtered
    if [ "${artifacts_2}" == "\"null\"" ] || [ "${artifacts_2}" == "null" ]; then
        echo "✅ Second release has no artifacts (expected - all components filtered, push-snapshot skipped)"
        echo "   First release pushed: ${artifacts_1}"
        echo "   Second release skipped push (idempotent)"
    elif [ "${artifacts_1}" == "${artifacts_2}" ]; then
        echo "✅ Both releases report identical artifact digests"
    else
        echo "First release artifacts: ${artifacts_1}"
        echo "Second release artifacts: ${artifacts_2}"
        log_error "Releases report different artifacts: ${artifacts_1} vs ${artifacts_2}"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ IDEMPOTENT RELEASE TEST PASSED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release pushed 1 component"
    echo "  • Second release filtered component (already released)"
    echo "  • Artifact consistency: Verified"
    echo "  • Idempotent behavior: ✅ CONFIRMED"
    echo ""
}
