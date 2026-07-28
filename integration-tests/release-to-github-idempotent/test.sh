#!/usr/bin/env bash
#
# test.sh - Test-specific functions for release-to-github-idempotent
#
# This test validates idempotent release-to-github behavior by:
#   1. Verifying the first (auto-created) release created a GitHub release and signed the blob
#   2. Creating a second release with the SAME snapshot
#   3. Verifying the second release detected the existing GitHub release and skipped creating a duplicate
#      (sign-base64-blob re-signs on each new run since each run starts with a fresh TA workspace;
#       its internal skip-if-sig-exists logic only applies to retries within the same pipeline run)
#
# This file is sourced by run-test.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# Get the managed PipelineRun name from a Release CR.
# The Release status stores the PipelineRun as "namespace/name"; returns just the name.
# Args: release_name
get_pipelinerun_name_from_release() {
    local release_name=$1

    local pipelinerun_full
    pipelinerun_full=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null) || true

    if [ -z "${pipelinerun_full}" ]; then
        return 1
    fi

    basename "${pipelinerun_full}"
}

# Fetch TaskRun logs for a named pipeline task in the managed namespace.
# Returns empty output (exit 0) when the TaskRun cannot be found or logs are unavailable,
# so callers can safely use grep on the result without `set -e` complications.
# Args: pipelinerun_name, pipeline_task_label
get_managed_task_logs() {
    local pipelinerun_name=$1
    local pipeline_task=$2

    local taskrun_name
    taskrun_name=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=${pipeline_task}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true

    if [ -z "${taskrun_name}" ]; then
        return 0
    fi

    tkn taskrun logs "${taskrun_name}" -n "${managed_namespace}" 2>/dev/null | tr -d '\000' || true
}

# Wait for a Release to complete, patching cleanup labels first.
# Args: release_name
wait_for_release() {
    local release_name=$1

    kubectl patch release "${release_name}" -n "${tenant_namespace}" \
        --type merge \
        -p "{\"metadata\":{\"labels\":{\"originating-tool\":\"${originating_tool}\",\"test-run-uuid\":\"${uuid}\"}}}" \
        2>/dev/null || true

    export RELEASE_NAME="${release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    "${SUITE_DIR}/../scripts/wait-for-release.sh"
}

patch_component_source() {
    echo "Patching component source..."
    set +x
    # Get secret value from the tenant secrets file and use it for GH_TOKEN
    secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")
    export GH_TOKEN=${secret_value}
    # Rename the file so that the github release task will create a new release
    # with the uuid-stamped tag we can assert on
    "${SCRIPT_DIR}/scripts/rename-github-file.sh" "${component_repo_name}" \
        "main_86.15272_SHA256SUMS" "main_86.${uuid}_SHA256SUMS" \
        -b "${component_branch}"
    echo "✅️ Successfully patched component source!"
}

# Verify Release contents - called by run-test.sh after first release completes.
# Implements the idempotent retrigger test logic:
#   Phase 1: Verify first release created a GitHub release at v86.${uuid}
#   Phase 2: Create second release with the same snapshot
#   Phase 3: Verify second release detected existing release/signature and skipped both
verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent GitHub Release Test - Phase 1: First Release Verification"
    echo "════════════════════════════════════════════════════════════════════"

    local first_release_name
    first_release_name=$(echo "${RELEASE_NAMES}" | awk '{print $1}')
    echo "First release: ${first_release_name}"

    local first_release_json
    first_release_json=$(kubectl get release "${first_release_name}" -n "${tenant_namespace}" -o json)

    # Verify first release URL
    local first_url
    first_url=$(jq -r '.status.artifacts."github-release".url // ""' <<< "${first_release_json}")
    echo "Checking GitHub release URL: ${first_url}..."
    if [ -n "${first_url}" ]; then
        local tag
        tag=$(awk -F'/' '{print $NF}' <<< "${first_url}")
        echo "Tag: ${tag}"
        if [ "${tag}" == "v86.${uuid}" ]; then
            echo "✅ Tag found (${tag}) matches expected v86.${uuid}"
            "${SUITE_DIR}/../scripts/verify-github-release.sh" "${component_repo_name}" "${tag}"
            echo "✅ GitHub release URL is valid and exists: ${first_url}"
        else
            log_error "Tag (${tag}) does not match expected v86.${uuid}"
        fi
    else
        log_error "GitHub release URL was empty in first release"
    fi

    # Verify first release advisory URL
    local first_advisory_url
    first_advisory_url="$(jq -r '.status.artifacts.advisory.url // ""' <<< "${first_release_json}" 2>/dev/null || true)"
    echo "Checking advisory URL..."
    if [ -n "${first_advisory_url}" ]; then
        echo "✅ advisory_url: ${first_advisory_url}"
    else
        log_error "advisory_url was empty in first release"
    fi
    echo "✅ First release verified successfully"

    # Capture asset list from the first release for later comparison
    local first_assets
    first_assets=$(gh release view "${tag}" --repo "${component_repo_name}" \
        --json assets --jq '[.assets[].name] | sort | .[]' 2>/dev/null)
    echo "First release assets:"
    echo "${first_assets}" | sed 's/^/  /'

    # Get snapshot from first release for reuse
    local snapshot_name
    snapshot_name=$(jq -r '.spec.snapshot' <<< "${first_release_json}")
    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Reusing snapshot: ${snapshot_name}"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent GitHub Release Test - Phase 2: Second Release (Retrigger)"
    echo "════════════════════════════════════════════════════════════════════"

    local second_release_name="github-idem-retry-${uuid}"
    echo "Creating second release: ${second_release_name} with same snapshot ${snapshot_name}"

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

    echo "Waiting for second release to complete..."
    wait_for_release "${second_release_name}"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent GitHub Release Test - Phase 3: Idempotent Behavior Verification"
    echo "════════════════════════════════════════════════════════════════════"

    local second_release_json
    second_release_json=$(kubectl get release "${second_release_name}" -n "${tenant_namespace}" -o json)
    local second_pipelinerun_name
    second_pipelinerun_name=$(get_pipelinerun_name_from_release "${second_release_name}") \
        || log_error "Could not retrieve managed PipelineRun name from second release ${second_release_name}"
    echo "Second release PipelineRun: ${second_pipelinerun_name}"

    local second_failures=0

    # Verify same GitHub release URL returned
    local second_url
    second_url=$(jq -r '.status.artifacts."github-release".url // ""' <<< "${second_release_json}")
    echo "Second release URL: ${second_url}"
    if [ "${first_url}" == "${second_url}" ]; then
        echo "✅ Both releases returned the same GitHub release URL"
    else
        echo "🔴 URLs differ: first=${first_url}, second=${second_url}"
        second_failures=$((second_failures + 1))
    fi

    # Verify second release has a non-empty advisory URL
    # Note: Unlike the RH advisories pipeline, release-to-github creates a new advisory for each release
    # (no already-released advisory filter), so the URLs may differ between runs.
    local second_advisory_url
    second_advisory_url="$(jq -r '.status.artifacts.advisory.url // ""' <<< "${second_release_json}" 2>/dev/null || true)"
    echo "Second release advisory URL: ${second_advisory_url}"
    if [ -n "${second_advisory_url}" ]; then
        echo "✅ Second release has advisory URL: ${second_advisory_url}"
    else
        echo "🔴 advisory_url was empty in second release"
        second_failures=$((second_failures + 1))
    fi

    # Verify create-github-release detected the existing release and skipped creation
    echo "Checking that create-github-release detected existing release..."
    local create_release_logs
    create_release_logs=$(get_managed_task_logs "${second_pipelinerun_name}" "create-github-release")
    if echo "${create_release_logs}" | grep -q "Release v.*exists"; then
        echo "✅ create-github-release detected existing release and skipped creation"
    else
        echo "🔴 create-github-release did not log 'Release v... exists'"
        second_failures=$((second_failures + 1))
    fi

    # Verify GitHub release assets are identical after the second run (no extra files uploaded)
    echo "Checking that no new assets were uploaded in the second run..."
    local second_assets
    second_assets=$(gh release view "${tag}" --repo "${component_repo_name}" \
        --json assets --jq '[.assets[].name] | sort | .[]' 2>/dev/null)
    echo "Second release assets:"
    echo "${second_assets}" | sed 's/^/  /'
    if [ "${first_assets}" == "${second_assets}" ]; then
        echo "✅ GitHub release assets are identical — no extra files uploaded by the second run"
    else
        echo "🔴 GitHub release assets differ between first and second run"
        echo "   First:  $(echo "${first_assets}" | tr '\n' ' ')"
        echo "   Second: $(echo "${second_assets}" | tr '\n' ' ')"
        second_failures=$((second_failures + 1))
    fi

    # Verify sign-base64-blob completed successfully in the second run.
    # Note: sign-base64-blob re-signs on every new pipeline run because each run
    # starts with a fresh Trusted Artifacts workspace (no .sig from a prior run).
    # Its internal idempotency check (if [ -f "$sig_file_path" ]) is designed for
    # retry-within-the-same-run scenarios, not cross-run idempotency.
    # The cross-run idempotency is handled by create-github-release, which checks
    # the GitHub API and skips uploading a duplicate release (verified above).
    echo "Checking that sign-base64-blob completed successfully in second run..."
    local sign_logs
    sign_logs=$(get_managed_task_logs "${second_pipelinerun_name}" "sign-base64-blob")
    if echo "${sign_logs}" | grep -q "done ("; then
        echo "✅ sign-base64-blob completed successfully in the second run"
    else
        echo "🔴 sign-base64-blob did not complete successfully in the second run"
        second_failures=$((second_failures + 1))
    fi

    if [ "${second_failures}" -gt 0 ]; then
        log_error "Idempotent behavior verification failed with ${second_failures} failure(s)"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ IDEMPOTENT GITHUB RELEASE TEST PASSED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release:  created GitHub release at v86.${uuid}"
    echo "  • Second release: detected existing release → skipped creation (no duplicate)"
    echo "  • Second release: sign-base64-blob re-signed (expected — fresh workspace per run)"
    echo "  • GitHub release URL consistent across both runs: ${first_url}"
    echo "  • Advisory URLs present in both releases"
    echo "  • No duplicate GitHub release created"
    echo "  • GitHub release assets identical across both runs (no extra files uploaded)"
    echo ""
}
