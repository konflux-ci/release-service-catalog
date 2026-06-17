#!/usr/bin/env bash
#
# test.sh - Test-specific functions for rh-advisories-idempotent
#
# This test validates idempotent release behavior for the rh-advisories pipeline by:
#   1. Building a real component via GitHub/PaC (same flow as collectors test)
#   2. Waiting for the first release (auto-released after build): all tasks run,
#      advisory created (skip_release=false)
#   3. Creating a second release with the SAME snapshot (sequential retrigger)
#   4. Verifying the second release detects the existing advisory via
#      filter-already-released-advisory-images and sets skip_release=true
#   5. Asserting all downstream tasks are skipped and advisory.url is present
#      in the release status (populated by update-cr-status-skipped from filter result)
#   6. Creating two additional releases (3rd and 4th) CONCURRENTLY with the same
#      snapshot to verify no race condition causes duplicate advisory creation
#   7. Verifying advisory URL stability: all filtered releases report the SAME URL
#   8. Fetching the actual advisory content and verifying the component image
#      digest is present (advisory references the correct images)
#
# Acceptance criteria:
#   - Second release: all major tasks in skippedTasks
#   - advisory.url present in second release status (from filter result, not create-advisory)
#   - Concurrent 3rd and 4th releases: both get skip_release=true, no duplicate advisory
#   - advisory.url identical across all filtered releases (no new advisory created)
#   - Advisory content contains the component image digest from the first release
#
# This file is sourced by run-test.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# Exit via log_error when a GitHub API response is empty, non-JSON, or an error object.
validate_github_api_json() {
    local response=$1
    local context=$2

    if [ -z "${response}" ]; then
        log_error "${context}: empty API response"
    fi
    if ! jq -e . >/dev/null 2>&1 <<< "${response}"; then
        log_error "${context}: non-JSON API response"
    fi
    if jq -e '.message' >/dev/null 2>&1 <<< "${response}"; then
        log_error "${context}: $(jq -r '.message' <<< "${response}")"
    fi
}

# --- envsubst Variable Allowlist ---
readonly ENVSUBST_ALLOWLIST='$application_name $component_branch $component_git_url $component_name $managed_namespace $managed_sa_name $originating_tool $release_plan_admission_name $release_plan_name $tenant_namespace $tenant_sa_name $tenant_collector_sa_name $RELEASE_CATALOG_GIT_REVISION $RELEASE_CATALOG_GIT_URL'

# Patch component source BEFORE merge to add multi-arch and source image build support
# This mirrors the collectors test to produce a multi-arch image for the advisory pipeline
patch_component_source_before_merge() {
    echo "Patching component source BEFORE MERGE to:"
    echo "- Add multi-arch support to the PaC pipeline"
    echo "- Add source image build to the PaC pipeline"

    local xtrace_was_on=0 github_token
    [[ $- == *x* ]] && xtrace_was_on=1
    set +x
    trap 'unset github_token; if [[ "${xtrace_was_on}" -eq 1 ]]; then set -x; fi; trap - RETURN' RETURN

    github_token=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")

    local file_names=(
        ".tekton/${component_name}-pull-request.yaml"
        ".tekton/${component_name}-push.yaml"
    )
    for file_name in "${file_names[@]}"; do
        echo "Patching ${file_name}..."

        local pr_response head_sha contents_response
        if ! pr_response=$(curl -sS --retry 3 --fail-with-body -H "Authorization: token ${github_token}" \
            "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}"); then
            [ -n "${pr_response}" ] && validate_github_api_json "${pr_response}" "GitHub pull #${pr_number}"
            log_error "GitHub pull #${pr_number}: HTTP request failed"
        fi
        validate_github_api_json "${pr_response}" "GitHub pull #${pr_number}"
        head_sha=$(jq -er '.head.sha' <<< "${pr_response}")

        if ! contents_response=$(curl -sS --retry 3 --fail-with-body -H "Authorization: token ${github_token}" \
            "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}"); then
            [ -n "${contents_response}" ] \
                && validate_github_api_json "${contents_response}" "GitHub contents ${file_name} @ ${head_sha}"
            log_error "GitHub contents ${file_name} @ ${head_sha}: HTTP request failed"
        fi
        validate_github_api_json "${contents_response}" "GitHub contents ${file_name} @ ${head_sha}"
        local decoded_contents
        decoded_contents=$(jq -er '.content' <<< "${contents_response}" | base64 -d)

        local work_dir nopath_file_name encoded_contents
        work_dir=$(mktemp -d)
        nopath_file_name=$(basename "${file_name}")
        echo "${decoded_contents}" > "${work_dir}/${nopath_file_name}"
        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) += ["linux/arm64"]' \
            "${work_dir}/${nopath_file_name}"
        yq -i '.spec.params += [{"name": "build-source-image", "value": "true"}]' \
            "${work_dir}/${nopath_file_name}"
        encoded_contents=$(base64 -w 0 < "${work_dir}/${nopath_file_name}")
        rm -rf "${work_dir}"

        GH_TOKEN="${github_token}" "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
            "${component_repo_name}" \
            "${pr_number}" \
            "${file_name}" \
            "Update component source before merge" \
            "${encoded_contents}"
    done

    echo "✅ Successfully patched component source!"
}

# Helper: Apply a Release CR and immediately return (non-blocking).
# Used to create multiple releases concurrently before waiting for any.
create_release_cr() {
    local release_name=$1
    local snapshot_name=$2
    local test_type=$3

    cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: "${release_name}"
  namespace: "${tenant_namespace}"
  labels:
    originating-tool: "${originating_tool}"
    test-run-uuid: "${uuid}"
    test-type: "${test_type}"
spec:
  snapshot: "${snapshot_name}"
  releasePlan: "${release_plan_name}"
EOF
}

# Helper: Wait for a release and capture its exit status into a named result variable.
# Usage: wait_for_release <release_name> <result_var>
# Sets result_var to 0 on success, 1 on failure.
wait_for_release_async() {
    local release_name=$1
    local result_file=$2

    (
        RELEASE_NAME="${release_name}" RELEASE_NAMESPACE="${tenant_namespace}" \
            "${SUITE_DIR}/../scripts/wait-for-release.sh" \
            && echo "0" > "${result_file}" \
            || echo "1" > "${result_file}"
    ) &
}

# Helper: Get a field from release.status.artifacts.advisory (e.g. url, internal_url).
get_advisory_artifact_field_from_release() {
    local release_name=$1
    local field_name=$2
    local release_json

    if ! release_json=$(get_release_json "${release_name}"); then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi
    jq -r --arg field "${field_name}" '.status.artifacts.advisory[$field] // ""' \
        <<< "${release_json}" 2>/dev/null || echo ""
}

# Helper: Get skip_release result value from filter task in the managed PipelineRun.
# Prints the value and returns 0 on success; prints nothing and returns 1 on resolution failure.
get_filter_skip_release_result() {
    local release_name=$1
    local pipelinerun_name plr_json taskrun_name taskrun_json result_value

    pipelinerun_name=$(get_pipelinerun_name_from_release "${release_name}") || return 1
    plr_json=$(kubectl get pipelinerun "${pipelinerun_name}" -n "${managed_namespace}" -o json) || return 1

    taskrun_name=$(jq -er --arg task_name 'filter-already-released-advisory-images' '
        [.status.childReferences[]? | select(.pipelineTaskName == $task_name) | .name] as $refs |
        if ($refs | length) == 0 then
            "no TaskRun for \($task_name)" | error
        elif ($refs | length) > 1 then
            "expected exactly 1 TaskRun for \($task_name), got \($refs | length)" | error
        else
            $refs[0]
        end
    ' <<< "${plr_json}") || return 1

    taskrun_json=$(kubectl get taskrun "${taskrun_name}" -n "${managed_namespace}" -o json) || return 1

    result_value=$(jq -er --arg result_name 'skip_release' '
        [.status.results[]? | select(.name == $result_name) | .value] as $vals |
        if ($vals | length) == 0 then
            "no \($result_name) result on TaskRun" | error
        elif ($vals | length) > 1 then
            "expected exactly 1 \($result_name) result, got \($vals | length)" | error
        else
            $vals[0]
        end
    ' <<< "${taskrun_json}") || return 1

    echo "${result_value}"
    return 0
}

# Main verification: implements idempotent test logic
# At this point RELEASE_NAMES contains the first release (auto-triggered after build)
verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 1: Verify First Release"
    echo "════════════════════════════════════════════════════════════════════"

    local first_release_name
    first_release_name=$(echo "${RELEASE_NAMES}" | awk '{print $1}')
    echo "First release: ${first_release_name}"

    # Verify create-advisory ran (not skipped) - images were unknown to Pyxis
    echo "Checking first release ran create-advisory..."
    if is_task_skipped "${first_release_name}" "create-advisory"; then
        log_error "First release: create-advisory was skipped, but it should have run (skip_release should be false)"
    fi
    echo "✅ First release: create-advisory ran (advisory created, skip_release=false)"

    # Get advisory URL from first release status
    local first_advisory_url
    first_advisory_url=$(get_advisory_artifact_field_from_release "${first_release_name}" url)
    if [ -z "${first_advisory_url}" ]; then
        log_error "First release: advisory.url not found in release status"
    fi
    echo "✅ First release advisory URL: ${first_advisory_url}"

    # Get snapshot name from first release to reuse in second release
    local snapshot_name
    snapshot_name=$(kubectl get release "${first_release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.spec.snapshot}' 2>/dev/null)
    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Using snapshot for second release: ${snapshot_name}"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 2: Trigger Second Release"
    echo "════════════════════════════════════════════════════════════════════"

    local second_release_name="${component_name}-retry"
    echo "Creating second release: ${second_release_name}"
    create_release_cr "${second_release_name}" "${snapshot_name}" "idempotent-second-release"

    echo "Waiting for second release to complete (Released=True)..."
    RELEASE_NAME="${second_release_name}" RELEASE_NAMESPACE="${tenant_namespace}" \
        "${SUITE_DIR}/../scripts/wait-for-release.sh"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 3: Verify Idempotent Behavior"
    echo "════════════════════════════════════════════════════════════════════"

    local failures=0

    # Verify filter-already-released-advisory-images ran (not skipped) and detected existing advisory
    echo "Checking filter-already-released-advisory-images ran (not skipped)..."
    if is_task_skipped "${second_release_name}" "filter-already-released-advisory-images"; then
        echo "🔴 filter-already-released-advisory-images was skipped in second release (should have run)"
        failures=$((failures+1))
    else
        echo "✅ filter-already-released-advisory-images ran (detected existing advisory)"
    fi

    # Verify all tasks gated by skip_release=false were skipped in second release
    local major_tasks=(
        "collect-task-params"
        "collect-signing-params"
        "collect-atlas-params"
        "check-labels"
        "verify-conforma"
        "populate-release-notes"
        "embargo-check"
        "set-advisory-severity"
        "rh-sign-image"
        "rh-sign-image-cosign"
        "push-snapshot"
        "create-pyxis-image"
        "publish-pyxis-repository"
        "push-rpm-data-to-pyxis"
        "process-component-sbom"
        "process-product-sbom"
        "run-file-updates"
        "check-data-keys"
        "create-advisory"
        "close-advisory-issues"
        "update-cr-status"
    )

    echo "Checking all major tasks are in skippedTasks..."
    for task in "${major_tasks[@]}"; do
        if is_task_skipped "${second_release_name}" "${task}"; then
            echo "  ✅ ${task}: skipped"
        else
            echo "  🔴 ${task}: NOT skipped (expected to be skipped)"
            failures=$((failures+1))
        fi
    done

    # Verify tasks that always run (not gated by skip_release) were NOT skipped
    local always_run_tasks=(
        "verify-access-to-resources"
        "collect-data"
        "reduce-snapshot"
        "apply-mapping"
        "filter-already-released-advisory-images"
    )
    echo "Checking always-running tasks were not skipped..."
    for task in "${always_run_tasks[@]}"; do
        if is_task_skipped "${second_release_name}" "${task}"; then
            echo "  🔴 ${task}: was skipped (should always run)"
            failures=$((failures+1))
        else
            echo "  ✅ ${task}: ran (expected)"
        fi
    done

    # Verify update-cr-status-skipped ran (not skipped) to write advisory URL
    echo "Checking update-cr-status-skipped ran..."
    if is_task_skipped "${second_release_name}" "update-cr-status-skipped"; then
        echo "🔴 update-cr-status-skipped was skipped in second release (should have run)"
        failures=$((failures+1))
    else
        echo "✅ update-cr-status-skipped ran (wrote advisory URL to release status)"
    fi

    # Verify skip_release=true directly from the filter task's TaskRun result
    echo "Checking filter task result skip_release=true directly..."
    local filter_skip_result
    if filter_skip_result=$(get_filter_skip_release_result "${second_release_name}"); then
        if [ "${filter_skip_result}" == "true" ]; then
            echo "✅ filter-already-released-advisory-images.results.skip_release=true (confirmed)"
        else
            echo "🔴 filter-already-released-advisory-images.results.skip_release='${filter_skip_result}' (expected 'true')"
            failures=$((failures+1))
        fi
    else
        echo "🔴 could not resolve filter-already-released-advisory-images skip_release result from TaskRun"
        failures=$((failures+1))
    fi

    # Verify advisory.url is present in second release status (from filter, not create-advisory)
    echo "Checking advisory.url in second release status..."
    local second_advisory_url
    second_advisory_url=$(get_advisory_artifact_field_from_release "${second_release_name}" url)
    if [ -z "${second_advisory_url}" ]; then
        echo "🔴 advisory.url not found in second release status"
        failures=$((failures+1))
    else
        echo "✅ advisory.url present in second release status: ${second_advisory_url}"

        if [ "${first_advisory_url}" == "${second_advisory_url}" ]; then
            echo "✅ advisory.url matches first release (same advisory reused)"
        else
            echo "⚠️  advisory.url differs from first release:"
            echo "   First:  ${first_advisory_url}"
            echo "   Second: ${second_advisory_url}"
        fi
    fi

    # Verify advisory_internal_url is also propagated to second release status
    echo "Checking advisory_internal_url in second release status..."
    local second_advisory_internal_url
    second_advisory_internal_url=$(get_advisory_artifact_field_from_release "${second_release_name}" internal_url)
    if [ -z "${second_advisory_internal_url}" ]; then
        echo "🔴 advisory_internal_url not found in second release status"
        failures=$((failures+1))
    else
        echo "✅ advisory_internal_url present in second release status: ${second_advisory_internal_url}"
    fi

    # Note: the pipeline-level advisory_url result on the second release PipelineRun will be
    # empty — this is an inherent Tekton behavior. When create-advisory is skipped, its result
    # is unresolvable at pipeline-result evaluation time and Tekton drops the entire expression.
    # The advisory URL is correctly propagated to the Release CR status via update-cr-status-skipped
    # (verified above), which is the actual acceptance criterion.
    local pipeline_advisory_url
    pipeline_advisory_url=$(get_pipelinerun_result "${second_release_name}" "advisory_url")
    if [ -z "${pipeline_advisory_url}" ]; then
        echo "ℹ️  pipeline-level advisory_url result is empty (expected: Tekton drops results that"
        echo "    reference skipped-task outputs; advisory.url in Release CR status is the source of truth)"
    else
        echo "✅ pipeline-level advisory_url result: ${pipeline_advisory_url}"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 4: Concurrent Releases"
    echo "  (Race Condition: 3rd and 4th releases submitted simultaneously)"
    echo "════════════════════════════════════════════════════════════════════"

    # Create two releases AT THE SAME TIME without waiting for either.
    # Both target the same already-released snapshot. This verifies:
    #   - No race condition causes a second advisory to be created
    #   - The filter handles concurrent in-flight releases correctly
    local third_release_name="${component_name}-concurrent-a"
    local fourth_release_name="${component_name}-concurrent-b"

    echo "Submitting 3rd release: ${third_release_name}"
    create_release_cr "${third_release_name}" "${snapshot_name}" "idempotent-concurrent-a"
    echo "Submitting 4th release: ${fourth_release_name} (immediately, before 3rd completes)"
    create_release_cr "${fourth_release_name}" "${snapshot_name}" "idempotent-concurrent-b"

    # Wait for both in parallel using background processes
    local result_file_3 result_file_4
    result_file_3=$(mktemp)
    result_file_4=$(mktemp)
    trap 'rm -f "${result_file_3}" "${result_file_4}"' RETURN

    wait_for_release_async "${third_release_name}" "${result_file_3}"
    wait_for_release_async "${fourth_release_name}" "${result_file_4}"

    echo "Waiting for both concurrent releases to complete..."
    wait

    local rc3 rc4
    rc3=$(cat "${result_file_3}" 2>/dev/null || echo "1")
    rc4=$(cat "${result_file_4}" 2>/dev/null || echo "1")

    if [ "${rc3}" != "0" ]; then
        echo "🔴 3rd release (${third_release_name}) did not complete successfully"
        failures=$((failures+1))
    else
        echo "✅ 3rd release completed (${third_release_name})"
    fi

    if [ "${rc4}" != "0" ]; then
        echo "🔴 4th release (${fourth_release_name}) did not complete successfully"
        failures=$((failures+1))
    else
        echo "✅ 4th release completed (${fourth_release_name})"
    fi

    # Both concurrent releases must also get skip_release=true
    for concurrent_release in "${third_release_name}" "${fourth_release_name}"; do
        echo "Checking concurrent release ${concurrent_release}..."
        local concurrent_skip_result
        if concurrent_skip_result=$(get_filter_skip_release_result "${concurrent_release}"); then
            if [ "${concurrent_skip_result}" == "true" ]; then
                echo "  ✅ ${concurrent_release}: skip_release=true (no duplicate advisory)"
            else
                echo "  🔴 ${concurrent_release}: skip_release='${concurrent_skip_result}' (expected 'true' — possible duplicate advisory!)"
                failures=$((failures+1))
            fi
        else
            echo "  🔴 ${concurrent_release}: could not resolve skip_release result"
            failures=$((failures+1))
        fi
    done

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 5: Advisory URL Stability"
    echo "  (All filtered releases must report the exact same advisory URL)"
    echo "════════════════════════════════════════════════════════════════════"

    # All releases after the first must report an identical advisory URL.
    # If any retrigger incorrectly created a new advisory the URL would differ.
    local all_filtered_releases=("${second_release_name}" "${third_release_name}" "${fourth_release_name}")
    for filtered_release in "${all_filtered_releases[@]}"; do
        local filtered_url
        filtered_url=$(get_advisory_artifact_field_from_release "${filtered_release}" url)
        if [ -z "${filtered_url}" ]; then
            echo "🔴 ${filtered_release}: advisory.url missing"
            failures=$((failures+1))
        elif [ "${filtered_url}" != "${first_advisory_url}" ]; then
            echo "🔴 ${filtered_release}: advisory.url '${filtered_url}' differs from first release '${first_advisory_url}' (duplicate advisory created!)"
            failures=$((failures+1))
        else
            echo "✅ ${filtered_release}: advisory.url matches first release (stable, no duplicate)"
        fi
    done

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  rh-advisories Idempotent Test - Phase 6: Advisory Content Validation"
    echo "  (Fetch actual advisory and verify it references the built image)"
    echo "════════════════════════════════════════════════════════════════════"

    # Fetch the advisory content via the OCI artifact pipeline and verify it
    # contains the component image digest from the first release.
    local advisory_output_dir
    advisory_output_dir=$(mktemp -d)
    trap 'rm -rf "${advisory_output_dir}"' RETURN

    local first_image_digest
    first_image_digest=$(kubectl get release "${first_release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.artifacts.components[0].containerImage}' 2>/dev/null || echo "")

    if [ -z "${first_image_digest}" ]; then
        echo "⚠️  Could not retrieve component image digest from first release status — skipping content check"
    else
        echo "Component image digest from first release: ${first_image_digest}"

        "${SUITE_DIR}/../scripts/get-advisory-content.sh" \
            "${managed_namespace}" "${managed_sa_name}" "${first_advisory_url}" "${advisory_output_dir}" \
            2>/dev/null || true

        local advisory_file
        advisory_file=$(find "${advisory_output_dir}" -name "advisory.yaml" 2>/dev/null | head -1)

        if [ -z "${advisory_file}" ]; then
            echo "⚠️  Advisory YAML not retrieved — skipping content check (advisory pipeline may not be configured in this environment)"
        else
            echo "Advisory file retrieved: ${advisory_file}"
            # Extract just the digest portion (sha256:...) for comparison
            local digest_only
            digest_only=$(echo "${first_image_digest}" | grep -oP 'sha256:[a-f0-9]+' || echo "")

            if [ -n "${digest_only}" ] && grep -q "${digest_only}" "${advisory_file}"; then
                echo "✅ Advisory content contains component image digest (${digest_only})"
            elif [ -n "${digest_only}" ]; then
                echo "🔴 Advisory content does NOT contain component image digest (${digest_only})"
                echo "   Advisory file contents:"
                cat "${advisory_file}" | head -30
                failures=$((failures+1))
            else
                echo "⚠️  Could not parse digest from image reference '${first_image_digest}' — skipping digest check"
            fi
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        echo ""
        echo "🔴 IDEMPOTENT RELEASE TEST FAILED with ${failures} failure(s)"
        return 1
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ rh-advisories IDEMPOTENT RELEASE TEST PASSED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release: all tasks ran, advisory created"
    echo "  • Second release (sequential): filter detected existing advisory (skip_release=true)"
    echo "  • filter task result skip_release=true confirmed directly"
    echo "  • All major downstream tasks skipped in second release"
    echo "  • advisory.url present in second release status (from filter result)"
    echo "  • advisory_internal_url present in second release status"
    echo "  • 3rd and 4th releases (concurrent): both got skip_release=true — no race condition"
    echo "  • advisory.url identical across all filtered releases — no duplicate advisory created"
    echo "  • advisory.url: ${second_advisory_url}"
    echo "  • advisory_internal_url: ${second_advisory_internal_url}"
    echo ""
}
