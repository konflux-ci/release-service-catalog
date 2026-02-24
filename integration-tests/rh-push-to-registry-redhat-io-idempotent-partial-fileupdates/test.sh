#!/usr/bin/env bash
#
# test.sh - Partial Completion States (Pyxis complete, fileUpdates not merged)
#
# Sources idempotent test for helpers and flow; overrides verify_release_contents
# to assert second release PROCEEDS (push-snapshot runs) because fileUpdates MR is not merged.
#

# shellcheck source=../rh-push-to-registry-redhat-io-idempotent/test.sh
source "${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent/test.sh"

# Override: expect second release to NOT skip (fileUpdates not complete)
verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Partial Completion Test - Phase 1: First Release Verification"
    echo "════════════════════════════════════════════════════════════════════"

    local first_release_name
    first_release_name=$(echo "${RELEASE_NAMES}" | awk '{print $1}')
    echo "First release: ${first_release_name}"

    if were_all_components_filtered "${first_release_name}"; then
        log_error "First release should NOT have filtered components, but push-snapshot was skipped"
    fi
    echo "✅ First release pushed components (expected)"

    if ! verify_single_release "${first_release_name}"; then
        log_error "First release verification failed"
    fi
    verify_pyxis_write_succeeded "${first_release_name}"

    local first_release_json
    first_release_json=$(get_release_json "${first_release_name}")
    local snapshot_name
    snapshot_name=$(jq -r '.spec.snapshot' <<< "${first_release_json}")
    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Using snapshot: ${snapshot_name}"

    local image_digest
    image_digest=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${first_release_json}")
    if [ -n "${image_digest}" ] && [ "${image_digest}" != "null" ]; then
        echo "Image digest to verify: ${image_digest}"
        if ! wait_for_pyxis_indexing_from_cluster "${managed_namespace}" "${component_name}" "${image_digest}"; then
            echo "⚠️  Pyxis RPM indexing timed out — proceeding anyway."
            echo "   This test validates fileUpdates behavior, not Pyxis RPM completeness."
            echo "   The filter will not skip the second release regardless of Pyxis RPM state,"
            echo "   because fileUpdates MR is not merged."
        fi
    else
        local wait_seconds="${IDEMPOTENT_WAIT_SECONDS:-60}"
        echo "Waiting ${wait_seconds}s for Pyxis propagation..."
        sleep "${wait_seconds}"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Partial Completion Test - Phase 2: Second Release (Expect Proceed)"
    echo "════════════════════════════════════════════════════════════════════"

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
    test-type: "idempotent-partial-fileupdates"
spec:
  snapshot: ${snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    echo "Waiting for second release to complete..."
    export RELEASE_NAME="${second_release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    "${SUITE_DIR}/../scripts/wait-for-release.sh"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Partial Completion Test - Phase 3: Fail-Safe Verification"
    echo "════════════════════════════════════════════════════════════════════"

    echo "Checking second release (fileUpdates not merged → should proceed, not skip)..."
    if were_all_components_filtered "${second_release_name}"; then
        echo ""
        echo "🔴 Second release skipped push-snapshot, but fileUpdates MR is not merged."
        echo "   Filter should have returned skip_release=false and allowed release to proceed."
        log_error "Partial completion test failed: second release should have run push-snapshot"
    fi
    echo "✅ Second release proceeded as expected (push-snapshot ran; fileUpdates not complete)"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ PARTIAL COMPLETION TEST PASSED (Gap 3.2)"
    echo "════════════════════════════════════════════════════════════════════"
    echo "Summary: Pyxis complete, fileUpdates pending → filter did not over-filter; release proceeded."
    echo ""
}
