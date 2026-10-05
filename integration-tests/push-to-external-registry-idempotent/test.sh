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


patch_component_source_before_merge() {
    if [[ "${PTSV_BUILD_PIPELINE}" != "docker-build-multi-platform-oci-ta" ]] \
        || [[ " ${PTSV_EXPECTED_ARCHES} " != *" arm64 "* ]]; then
        echo "Not a multi-arch run, skipping build-platforms patch"
        return 0
    fi

    set +x
    secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")
    export GH_TOKEN="${secret_value}"

    local pr_response
    pr_response=$(curl -sS --retry 3 --fail-with-body -H "Authorization: token ${GH_TOKEN}" \
        "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}")
    head_sha=$(jq -r '.head.sha' <<< "${pr_response}")
    head_ref=$(jq -r '.head.ref' <<< "${pr_response}")
    head_repo_full_name=$(jq -r '.head.repo.full_name' <<< "${pr_response}")

    local file_names=".tekton/${component_name}-pull-request.yaml .tekton/${component_name}-push.yaml "
    for file_name in ${file_names}; do
        local work_dir
        work_dir=$(mktemp -d)
        nopath_file_name=$(basename "${file_name}")

        curl -s -H "Authorization: token ${GH_TOKEN}" \
            "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}" | \
            jq -r '.content' | base64 -d > "${work_dir}/${nopath_file_name}"

        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) += ["linux/arm64"]' \
            "${work_dir}/${nopath_file_name}"
        encoded_contents=$(base64 -w 0 "${work_dir}/${nopath_file_name}")
        rm -rf "${work_dir}"

        "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
            "${component_repo_name}" \
            "${pr_number}" \
            "${file_name}" \
            "Update component source before merge" \
            "${encoded_contents}" \
            "${head_ref}" \
            "${head_repo_full_name}"
    done
}

# Pick the release whose snapshot contains the most components.
# Konflux emits a snapshot (and release) per component build. The earliest
# release only contains the first component; a later one contains all of them.
# Diagnostics go to stderr so command substitution captures only the name.
# Arguments: $1 = expected component count
select_release_for_verification() {
    local expected_count="${1}"
    local -a release_names=()
    local release_name best_release="" best_count=0

    read -r -a release_names <<< "${RELEASE_NAMES}"
    if [ "${#release_names[@]}" -eq 0 ]; then
        echo "🔴 RELEASE_NAMES is empty" >&2
        return 1
    fi

    if [ "${expected_count}" -le 1 ]; then
        printf '%s' "${release_names[0]}"
        return 0
    fi

    echo "Multi-component test: looking for a release with ${expected_count} components..." >&2
    for release_name in "${release_names[@]}"; do
        local rel_json snap_name snap_json comp_count
        if ! rel_json="$(kubectl get release "${release_name}" -n "${tenant_namespace}" -o json 2>/dev/null)"; then
            echo "  Warning: failed to fetch release ${release_name}" >&2
            continue
        fi
        snap_name="$(jq -r '.spec.snapshot // ""' <<< "${rel_json}")"
        if [ -z "${snap_name}" ] || [ "${snap_name}" = "null" ]; then
            echo "  Warning: release ${release_name} has no snapshot" >&2
            continue
        fi
        if ! snap_json="$(kubectl get snapshot "${snap_name}" -n "${tenant_namespace}" -o json 2>/dev/null)"; then
            echo "  Warning: failed to fetch snapshot ${snap_name}" >&2
            continue
        fi
        if ! comp_count="$(jq -r '(.spec.components // []) | length' <<< "${snap_json}")"; then
            echo "  Warning: failed to count components in snapshot ${snap_name}" >&2
            continue
        fi
        echo "  Release ${release_name} -> snapshot ${snap_name} has ${comp_count} component(s)" >&2
        if [ -z "${best_release}" ] || [ "${comp_count}" -gt "${best_count}" ]; then
            best_count="${comp_count}"
            best_release="${release_name}"
        fi
    done

    if [ -z "${best_release}" ]; then
        echo "🔴 Could not read component counts for any release" >&2
        return 1
    fi
    if [ "${best_count}" -lt "${expected_count}" ]; then
        echo "🔴 Fullest release ${best_release} has ${best_count} component(s), expected ${expected_count}" >&2
        return 1
    fi
    echo "Selected release with the most components: ${best_release} (${best_count} components)" >&2
    printf '%s' "${best_release}"
}

# Check if all components were filtered (idempotency validation)
# Returns 0 (true) if push-snapshot task was skipped, 1 (false) otherwise
were_all_components_filtered() {
    local release_name=$1

    # Check if all components were filtered by seeing if push-snapshot was skipped
    is_task_skipped "${release_name}" "push-snapshot"
}

# Verify a release has valid artifacts for all components and images can be pulled
verify_single_release() {
    local release_name=$1
    echo "Verifying Release contents for ${release_name}..."

    local release_json
    release_json=$(get_release_json "${release_name}")
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi

    # Set RELEASE_NAME for check_container_images (it expects this global)
    local RELEASE_NAME="${release_name}"
    local failures=0
    local failed_releases=""

    # Verify container images using shared helper (single-arch)
    check_container_images

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Release verification FAILED with ${failures} failure(s)!"
        return 1
    else
        local image_count
        image_count=$(jq -r '.status.artifacts.images | length' <<< "${release_json}")
        echo "✅️ All release checks passed for ${image_count} image(s)."
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

    # RELEASE_NAMES is set by wait_for_releases in run-test.sh.
    # For multi-component runs it includes the partial first-component release.
    local expected_component_count first_release_name
    expected_component_count="$(echo "${PTSV_COMPONENTS}" | wc -w | tr -d '[:space:]')"
    if ! first_release_name="$(select_release_for_verification "${expected_component_count}")"; then
        log_error "Could not select a release covering ${expected_component_count} component(s)"
    fi

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

    # Verify artifact consistency across ALL images (multi-component support)
    echo ""
    echo "Verifying artifact consistency..."
    local second_release_json
    second_release_json=$(get_release_json "${second_release_name}")

    # Extract sorted list of all image shasums for comparison
    local artifacts_1 artifacts_2
    artifacts_1=$(jq -S '[.status.artifacts.images[]?.shasum // empty] | sort' <<< "${first_release_json}")
    artifacts_2=$(jq -S '[.status.artifacts.images[]?.shasum // empty] | sort' <<< "${second_release_json}")

    local artifact_count_1 artifact_count_2
    artifact_count_1=$(jq -r 'length' <<< "${artifacts_1}")
    artifact_count_2=$(jq -r 'length' <<< "${artifacts_2}")

    # Second release may have no artifacts if all components were filtered
    if [ "${artifact_count_2}" -eq 0 ]; then
        echo "✅ Second release has no artifacts (expected - all components filtered, push-snapshot skipped)"
        echo "   First release pushed ${artifact_count_1} image(s)"
        echo "   Second release skipped push (idempotent)"
    elif [ "${artifacts_1}" == "${artifacts_2}" ]; then
        echo "✅ Both releases report identical artifact digests for all ${artifact_count_1} image(s)"
    else
        echo "First release artifacts (${artifact_count_1}):"
        jq -r '.[]' <<< "${artifacts_1}" | while read -r shasum; do echo "  - ${shasum}"; done
        echo "Second release artifacts (${artifact_count_2}):"
        jq -r '.[]' <<< "${artifacts_2}" | while read -r shasum; do echo "  - ${shasum}"; done
        log_error "Releases report different artifacts"
    fi

    local component_count
    component_count=$(echo "${PTSV_COMPONENTS}" | wc -w)

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ IDEMPOTENT RELEASE TEST PASSED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release pushed ${component_count} component(s)"
    echo "  • Second release filtered all components (already released)"
    echo "  • Artifact consistency: Verified"
    echo "  • Idempotent behavior: ✅ CONFIRMED"
    echo ""
}
