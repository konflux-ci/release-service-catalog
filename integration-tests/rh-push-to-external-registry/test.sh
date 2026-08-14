#!/usr/bin/env bash
#
# test.sh - Test-specific functions for rh-push-to-external-registry
#
# This test validates idempotent release behavior by:
#   1. Verifying the first (auto-created) release pushed images to registry and Pyxis
#   2. Verifying first release skip_release result is "false"
#   3. Verifying Pyxis images exist with RPM manifests after first release
#   4. Creating a second release with the SAME snapshot
#   5. Verifying second release skip_release result is "true" (primary idempotency signal)
#   6. Verifying all four downstream tasks are in skippedTasks (secondary validation)
#   7. Verifying artifact consistency between releases
#
# Acceptance criteria:
#   - First release: skip_release="false", Pyxis images created with RPM manifests
#   - Second release: skip_release="true", all four downstream tasks in skippedTasks
#     (verify-conforma, push-snapshot, create-pyxis-image, push-rpm-data-to-pyxis)
#
# Note: The skip_release result from filter-already-released-images is the authoritative
# signal for idempotency. The skippedTasks checks are secondary validation. Pyxis image
# count is implicitly unchanged when create-pyxis-image is skipped.
#
# This file is sourced by run-test.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # Default to false

# Pyxis API base URL
PYXIS_URL="https://pyxis.preprod.api.redhat.com/"

# Check if all components were filtered (idempotency validation)
# Returns 0 (true) if push-snapshot task was skipped, 1 (false) otherwise
were_all_components_filtered() {
    local release_name="${1}"
    is_task_skipped "${release_name}" "push-snapshot"
}

# Cleanup Pyxis credential files (idempotent - safe to call multiple times)
cleanup_pyxis_credentials() {
    [ -n "${PYXIS_CERT_FILE}" ] && [ -f "${PYXIS_CERT_FILE}" ] && rm -f "${PYXIS_CERT_FILE}"
    [ -n "${PYXIS_KEY_FILE}" ] && [ -f "${PYXIS_KEY_FILE}" ] && rm -f "${PYXIS_KEY_FILE}"
    unset PYXIS_CERT_FILE PYXIS_KEY_FILE
}

# Get Pyxis credentials from managed secrets and prepare cert/key files
# Sets global PYXIS_CERT_FILE and PYXIS_KEY_FILE
# Registers EXIT trap to ensure cleanup even on script exit/failure
setup_pyxis_credentials() {
    local cert_secret_encoded key_secret_encoded
    local pyxis_secret_name="pyxis-${component_name}"

    # Select the exact secret name used in the RPA (pyxis-${component_name})
    # Fail fast if the secret is missing or if the selector matches multiple documents
    cert_secret_encoded="$(yq -e "select(.metadata.name == \"${pyxis_secret_name}\") | .data.cert" \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml")" || {
        echo "🔴 Could not find .data.cert in secret '${pyxis_secret_name}'" >&2
        return 1
    }
    key_secret_encoded="$(yq -e "select(.metadata.name == \"${pyxis_secret_name}\") | .data.key" \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml")" || {
        echo "🔴 Could not find .data.key in secret '${pyxis_secret_name}'" >&2
        return 1
    }

    # Validate we got exactly one value (no newlines from multiple matches)
    if [[ "${cert_secret_encoded}" == *$'\n'* ]]; then
        echo "🔴 Multiple matches for secret '${pyxis_secret_name}' - check managed-secrets.yaml" >&2
        return 1
    fi

    PYXIS_CERT_FILE="$(mktemp)"
    PYXIS_KEY_FILE="$(mktemp)"
    base64 -d <<< "${cert_secret_encoded}" > "${PYXIS_CERT_FILE}"
    base64 -d <<< "${key_secret_encoded}" > "${PYXIS_KEY_FILE}"

    # Chain cleanup into existing EXIT trap to ensure credentials are removed
    # even when log_error calls exit and bypasses normal function return.
    # Run existing trap FIRST to preserve $? for cleanup_resources, then clean up credentials.
    local existing_trap
    existing_trap="$(trap -p EXIT | sed "s/^trap -- '\\(.*\\)' EXIT$/\\1/")"
    if [ -n "${existing_trap}" ]; then
        trap "${existing_trap}; cleanup_pyxis_credentials" EXIT
    else
        trap 'cleanup_pyxis_credentials' EXIT
    fi
}

# Get Pyxis image IDs from a release's OCI artifact
# Arguments: $1=release_name
# Prints space-separated list of image IDs
get_pyxis_image_ids_from_release() {
    local release_name="${1}"
    local managed_plr_name uri oci_artifact
    local oci_artifact_dir image_ids
    local -a pyxis_files

    managed_plr_name="$(get_pipelinerun_name_from_release "${release_name}")" || {
        echo "🔴 Could not get PipelineRun name for release ${release_name}" >&2
        return 1
    }
    if [[ -z "${managed_plr_name}" || "${managed_plr_name}" == "null" ]]; then
        echo "🔴 PipelineRun name is empty or null for release ${release_name}" >&2
        return 1
    fi

    uri="$("${SCRIPT_DIR}/scripts/get-taskrun-result.sh" "${managed_plr_name}" "create-pyxis-image" \
        "sourceDataArtifact" "${managed_namespace}")"
    oci_artifact="${uri#*:}"

    oci_artifact_dir="$(mktemp -d -p "$(pwd)")"

    # Use a subshell-based cleanup pattern to avoid global trap pollution.
    # The subshell ensures the temp directory is removed even on early exit,
    # and the trap is scoped to the subshell only.
    image_ids="$(
        trap 'rm -rf "${oci_artifact_dir}"' EXIT
        oras blob fetch "${oci_artifact}" --output - | tar -C "${oci_artifact_dir}" --no-overwrite-dir -zxmf -

        mapfile -t pyxis_files < <(find "${oci_artifact_dir}" -name "pyxis.json")
        if (( ${#pyxis_files[@]} != 1 )); then
            echo "🔴 Expected exactly 1 pyxis.json, found ${#pyxis_files[@]}" >&2
            exit 1
        fi

        jq -r '[.components[].pyxisImages[].imageId] | join(" ")' "${pyxis_files[0]}"
    )" || return 1

    echo "${image_ids}"
}

# Get the skip_release result from filter-already-released-images task
# Arguments: $1=release_name
# Prints the skip_release value ("true" or "false")
# Returns 1 if the result cannot be retrieved
get_skip_release_result() {
    local release_name="${1}"
    local pipelinerun_name skip_release

    pipelinerun_name="$(get_pipelinerun_name_from_release "${release_name}")" || {
        echo "🔴 Could not get PipelineRun name for release ${release_name}" >&2
        return 1
    }

    skip_release="$("${SCRIPT_DIR}/scripts/get-taskrun-result.sh" "${pipelinerun_name}" \
        "filter-already-released-images" "skip_release" "${managed_namespace}")" || {
        echo "🔴 Could not get skip_release result from filter-already-released-images task" >&2
        return 1
    }

    if [[ -z "${skip_release}" || "${skip_release}" == "null" ]]; then
        echo "🔴 skip_release result is empty or null" >&2
        return 1
    fi

    echo "${skip_release}"
}

# Verify Pyxis images exist and have RPM manifests
# Arguments: $1=space-separated image IDs
# Returns: 0 if all verified, non-zero if any failures
verify_pyxis_images() {
    local -a image_ids_arr
    local failures=0 image_id result_json result_id rpm_json rpm_manifest_id

    read -ra image_ids_arr <<< "${1}"
    for image_id in "${image_ids_arr[@]}"; do
        if ! result_json="$(curl --retry 3 --silent --show-error --fail-with-body \
            --cert "${PYXIS_CERT_FILE}" --key "${PYXIS_KEY_FILE}" \
            "${PYXIS_URL}v1/images/id/${image_id}")"; then
            echo "🔴 Pyxis API request failed for imageId: ${image_id}"
            failures=$((failures + 1))
            continue
        fi
        result_id="$(jq -r '._id // ""' <<< "${result_json}")"
        if [ "${result_id}" == "${image_id}" ]; then
            echo "✅ Found imageId: ${result_id} in Pyxis"
        else
            echo "🔴 imageId: ${result_id} did not match expected imageId: ${image_id}"
            failures=$((failures + 1))
        fi

        if ! rpm_json="$(curl --retry 3 --silent --show-error --fail-with-body \
            --cert "${PYXIS_CERT_FILE}" --key "${PYXIS_KEY_FILE}" \
            "${PYXIS_URL}v1/images/id/${image_id}/rpm-manifest")"; then
            echo "🔴 Pyxis API request failed for RPM manifest of imageId: ${image_id}"
            failures=$((failures + 1))
            continue
        fi
        rpm_manifest_id="$(jq -r '._id // ""' <<< "${rpm_json}")"
        if [ -n "${rpm_manifest_id}" ]; then
            echo "✅ Found RPM manifest for imageId: ${image_id} in Pyxis"
        else
            echo "🔴 No RPM manifest found for imageId: ${image_id}"
            failures=$((failures + 1))
        fi
    done

    return "${failures}"
}

# Verify a release has valid artifacts for all components and images can be pulled
verify_single_release() {
    local release_name="${1}"
    echo "Verifying Release contents for ${release_name}..."

    local release_json
    release_json="$(get_release_json "${release_name}")"
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi

    # Set RELEASE_NAME for check_container_images (it expects this global)
    local RELEASE_NAME="${release_name}"
    # check_container_images increments 'failures' for image-count check and
    # appends to 'failed_releases' for per-image failures
    local failures=0
    local failed_releases=""

    # Verify container images using shared helper
    check_container_images

    # Check both the outer failures count and per-image failures tracked in failed_releases
    if [ "${failures}" -gt 0 ] || [[ -n "${failed_releases}" ]]; then
        echo "🔴 Release verification FAILED!"
        [[ -n "${failed_releases}" ]] && echo "   Failed releases: ${failed_releases}"
        return 1
    else
        local image_count
        image_count="$(jq -r '.status.artifacts.images | length' <<< "${release_json}")"
        echo "✅️ All release checks passed for ${image_count} image(s)."
        return 0
    fi
}

patch_component_source_before_merge() {
    set +x
    secret_value="$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")"
    export GH_TOKEN="${secret_value}"

    local pr_response head_sha
    if ! pr_response="$(curl --retry 3 --silent --show-error --fail-with-body \
        -H "Authorization: token ${GH_TOKEN}" \
        "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}")"; then
        log_error "GitHub API request failed for PR ${pr_number}"
    fi
    head_sha="$(jq -r '.head.sha' <<< "${pr_response}")"
    if [ -z "${head_sha}" ] || [ "${head_sha}" == "null" ]; then
        log_error "Could not get head SHA from PR ${pr_number}"
    fi

    local -a file_names=(
        ".tekton/${component_name}-pull-request.yaml"
        ".tekton/${component_name}-push.yaml"
    )
    for file_name in "${file_names[@]}"; do
        local work_dir contents_response
        work_dir="$(mktemp -d)"
        nopath_file_name="$(basename "${file_name}")"

        if ! contents_response="$(curl --retry 3 --silent --show-error --fail-with-body \
            -H "Authorization: token ${GH_TOKEN}" \
            "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}")"; then
            rm -rf "${work_dir}"
            log_error "GitHub API request failed for ${file_name}"
        fi
        jq -r '.content' <<< "${contents_response}" | base64 -d > "${work_dir}/${nopath_file_name}"

        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) |= ((. + ["linux/arm64"]) | unique)' \
            "${work_dir}/${nopath_file_name}"
        encoded_contents="$(base64 -w 0 "${work_dir}/${nopath_file_name}")"
        rm -rf "${work_dir}"

        "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
            "${component_repo_name}" \
            "${pr_number}" \
            "${file_name}" \
            "Update component source before merge" \
            "${encoded_contents}"
    done
}

# Main verification: implements idempotent test logic
# At this point RELEASE_NAMES contains the first release (auto-triggered after build)
verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-push-to-external-registry Idempotent Test - Phase 1: First Release"
    echo "════════════════════════════════════════════════════════════════════"

    local first_release_name
    first_release_name="$(echo "${RELEASE_NAMES}" | awk '{print $1}')"
    if [[ -z "${first_release_name}" ]]; then
        echo "DEBUG: RELEASE_NAMES='${RELEASE_NAMES}'" >&2
        log_error "RELEASE_NAMES was empty; cannot determine first release name"
    fi
    echo "First release: ${first_release_name}"

    # Set up Pyxis credentials for API calls (cleaned up via EXIT trap)
    setup_pyxis_credentials

    # Verify first release was NOT filtered (components should be pushed)
    echo "Checking if first release pushed components..."
    if were_all_components_filtered "${first_release_name}"; then
        log_error "First release should NOT have filtered components, but push-snapshot was skipped"
    fi
    echo "✅ First release pushed components (expected behavior)"

    # Explicitly verify skip_release result is "false" for first release
    echo ""
    echo "Verifying skip_release result for first release..."
    local first_skip_release
    first_skip_release="$(get_skip_release_result "${first_release_name}")" || {
        log_error "Could not retrieve skip_release result for first release"
    }
    if [[ "${first_skip_release}" == "false" ]]; then
        echo "✅ First release skip_release=${first_skip_release} (expected)"
    else
        log_error "First release skip_release='${first_skip_release}', expected 'false'"
    fi

    # Verify first release artifacts
    if ! verify_single_release "${first_release_name}"; then
        log_error "First release verification failed"
    fi

    # Get Pyxis image IDs from first release and verify they exist with RPM manifests
    echo ""
    echo "Retrieving Pyxis image data from first release..."
    local first_release_image_ids
    first_release_image_ids="$(get_pyxis_image_ids_from_release "${first_release_name}")"
    echo "Image IDs from first release: ${first_release_image_ids}"

    local image_id_count
    image_id_count="$(echo "${first_release_image_ids}" | wc -w)"
    if [ "${image_id_count}" -lt 2 ]; then
        echo "🔴 Found only ${image_id_count} Pyxis image ID(s), expected at least 2 for multi-arch"
        log_error "Insufficient Pyxis images from first release"
    fi
    echo "✅ Found ${image_id_count} Pyxis image IDs (expected at least 2 for multi-arch)"

    # Verify images exist in Pyxis and have RPM manifests
    echo ""
    echo "Verifying Pyxis images and RPM manifests..."
    if ! verify_pyxis_images "${first_release_image_ids}"; then
        log_error "First release Pyxis image verification failed"
    fi

    # Get snapshot name from first release to reuse in second release
    local first_release_json snapshot_name
    first_release_json="$(get_release_json "${first_release_name}")"
    snapshot_name="$(jq -r '.spec.snapshot' <<< "${first_release_json}")"

    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Using snapshot: ${snapshot_name}"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-push-to-external-registry Idempotent Test - Phase 2: Second Release"
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
    test-run-uuid: "${uuid}"
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
    echo "  rh-push-to-external-registry Idempotent Test - Phase 3: Verification"
    echo "════════════════════════════════════════════════════════════════════"

    local failures=0

    # PRIMARY CHECK: Verify skip_release result is "true" for second release
    # This is the authoritative signal that the filter task correctly detected
    # already-released images. The skippedTasks checks below are secondary validation.
    echo "Verifying skip_release result for second release (primary idempotency signal)..."
    local second_skip_release
    second_skip_release="$(get_skip_release_result "${second_release_name}")" || {
        echo "🔴 Could not retrieve skip_release result for second release"
        failures=$((failures + 1))
    }
    if [[ -n "${second_skip_release}" ]]; then
        if [[ "${second_skip_release}" == "true" ]]; then
            echo "✅ Second release skip_release=${second_skip_release} (expected - idempotent)"
        else
            echo "🔴 Second release skip_release='${second_skip_release}', expected 'true'"
            failures=$((failures + 1))
        fi
    fi

    # Verify second release filtered all components (idempotent behavior)
    echo ""
    echo "Checking if second release filtered all components..."
    if were_all_components_filtered "${second_release_name}"; then
        echo "✅ Second release filtered all components (idempotent behavior confirmed)"
    else
        echo "🔴 Second release should have filtered all components, but push-snapshot ran"
        failures=$((failures + 1))
    fi

    # SECONDARY VALIDATION: Verify all four downstream tasks are in skippedTasks
    # These checks complement the skip_release verification above
    local downstream_tasks=(
        "verify-conforma"
        "push-snapshot"
        "create-pyxis-image"
        "push-rpm-data-to-pyxis"
    )

    echo ""
    echo "Checking all four downstream tasks are in skippedTasks..."
    for task in "${downstream_tasks[@]}"; do
        if is_task_skipped "${second_release_name}" "${task}"; then
            echo "  ✅ ${task}: skipped"
        else
            echo "  🔴 ${task}: NOT skipped (expected to be skipped)"
            failures=$((failures + 1))
        fi
    done

    # Verify tasks that always run (not gated by skip_release) actually executed
    local always_run_tasks=(
        "verify-access-to-resources"
        "collect-data"
        "reduce-snapshot"
        "apply-mapping"
        "filter-already-released-images"
    )
    echo ""
    echo "Checking always-running tasks actually executed..."
    for task in "${always_run_tasks[@]}"; do
        if ! did_task_run "${second_release_name}" "${task}"; then
            echo "  🔴 ${task}: not found in childReferences (task did not run)"
            failures=$((failures + 1))
        elif is_task_skipped "${second_release_name}" "${task}"; then
            echo "  🔴 ${task}: was skipped (should always run)"
            failures=$((failures + 1))
        else
            echo "  ✅ ${task}: ran (expected)"
        fi
    done

    # Verify artifact consistency
    echo ""
    echo "Verifying artifact consistency..."
    local second_release_json
    second_release_json="$(get_release_json "${second_release_name}")"

    # Get actual image counts (not shasum counts, to detect missing shasums)
    local image_count_1 image_count_2
    image_count_1="$(jq -r '(.status.artifacts.images // []) | length' <<< "${first_release_json}")"
    image_count_2="$(jq -r '(.status.artifacts.images // []) | length' <<< "${second_release_json}")"

    # If images exist, verify all have valid shasums
    local valid_shasum_count_1 valid_shasum_count_2
    valid_shasum_count_1="$(jq -r '[.status.artifacts.images[]? | .shasum? | select(. != null and . != "")] | length' <<< "${first_release_json}")"
    valid_shasum_count_2="$(jq -r '[.status.artifacts.images[]? | .shasum? | select(. != null and . != "")] | length' <<< "${second_release_json}")"

    if [ "${image_count_1}" -gt 0 ] && [ "${valid_shasum_count_1}" -ne "${image_count_1}" ]; then
        echo "🔴 First release has ${image_count_1} image artifact(s) but only ${valid_shasum_count_1} valid shasum(s)"
        failures=$((failures + 1))
    elif [ "${image_count_2}" -gt 0 ] && [ "${valid_shasum_count_2}" -ne "${image_count_2}" ]; then
        echo "🔴 Second release has ${image_count_2} image artifact(s) but only ${valid_shasum_count_2} valid shasum(s)"
        failures=$((failures + 1))
    elif [ "${image_count_2}" -eq 0 ]; then
        echo "✅ Second release has no artifacts (expected - all components filtered, push-snapshot skipped)"
        echo "   First release pushed ${image_count_1} image(s)"
        echo "   Second release skipped push (idempotent)"
    else
        # Both have images with valid shasums - compare sorted shasum lists
        local artifacts_1 artifacts_2
        artifacts_1="$(jq -S '[.status.artifacts.images[].shasum] | sort' <<< "${first_release_json}")"
        artifacts_2="$(jq -S '[.status.artifacts.images[].shasum] | sort' <<< "${second_release_json}")"

        if [ "${artifacts_1}" == "${artifacts_2}" ]; then
            echo "✅ Both releases report identical artifact digests for all ${image_count_1} image(s)"
        else
            echo "First release artifacts (${image_count_1}):"
            jq -r '.[]' <<< "${artifacts_1}" | while read -r shasum; do echo "  - ${shasum}"; done
            echo "Second release artifacts (${image_count_2}):"
            jq -r '.[]' <<< "${artifacts_2}" | while read -r shasum; do echo "  - ${shasum}"; done
            echo "🔴 Releases report different artifacts"
            failures=$((failures + 1))
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        echo ""
        echo "🔴 IDEMPOTENT RELEASE TEST FAILED with ${failures} failure(s)"
        return 1
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ rh-push-to-external-registry IDEMPOTENT RELEASE TEST PASSED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release: image pushed, Pyxis image created, RPM data uploaded"
    echo "  • Second release (same Snapshot): all downstream tasks skipped"
    echo "  • Downstream tasks skipped: verify-conforma, push-snapshot, create-pyxis-image, push-rpm-data-to-pyxis"
    echo "  • Idempotent behavior: ✅ CONFIRMED"
    echo ""
}
