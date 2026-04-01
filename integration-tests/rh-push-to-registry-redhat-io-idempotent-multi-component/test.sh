#!/usr/bin/env bash
#
# test.sh - Multi-component idempotent test (Heterogeneous Snapshot Filtering)
#
# Validates filter and idempotency with 2 components: first release pushes both,
# second release filters both. Reuses idempotent verify logic; overrides repo/PR/PLR/release flow.
#

# --- Load idempotent test logic (helpers + verify_release_contents) ---
# shellcheck source=../rh-push-to-registry-redhat-io-idempotent/test.sh
source "${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent/test.sh"

# --- Overrides for multi-component flow ---

decrypt_secrets() {
    # Use base suite's vault — multi-component shares the same credentials
    local base_suite_dir="${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent"
    (
        . "${LIB_DIR}/test-functions.sh"
        decrypt_secrets "${base_suite_dir}"
    )
    # Copy decrypted tenant secrets from base suite (contains real GitHub token)
    local base_tenant_secrets="${base_suite_dir}/resources/tenant/secrets/tenant-secrets.yaml"
    local tenant_secrets_file="${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml"
    mkdir -p "${SUITE_DIR}/resources/tenant/secrets"
    cp "${base_tenant_secrets}" "${tenant_secrets_file}"

    local component2_file="${SUITE_DIR}/resources/tenant/secrets/tenant-secrets-component2.yaml"
    if [ -f "${tenant_secrets_file}" ] && [ -n "${component2_name:-}" ]; then
        sed -e 's/\${component_name}/\${component2_name}/g' -e "s|\${component_repo_name}|\${component2_repo_name}|g" \
            "${tenant_secrets_file}" > "${component2_file}"
        echo "Created ${component2_file} for component2."
    fi
}

create_github_repository() {
    echo "Creating repositories for both components (same repo, two branches)..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component2_repo_name}" "${component2_branch}"
}

wait_for_component_initialization() {
    echo "Waiting for both components to initialize..."
    wait_for_single_component_initialization "${component_name}"
    component_pr_number="${pr_number}"
    wait_for_single_component_initialization "${component2_name}"
    component2_pr_number="${pr_number}"
    pr_number="${component_pr_number}"
}

merge_github_pr() {
    echo "Merging PRs for both components..."
    merge_single_component_pr "${component_pr_number}" "${component_repo_name}"
    component_sha="${SHA}"
    merge_single_component_pr "${component2_pr_number}" "${component2_repo_name}"
    component2_sha="${SHA}"
    SHA="${component_sha}"
}

wait_for_plr_to_appear() {
    echo "Waiting for PipelineRuns for both components..."
    comp1_plr=$(wait_for_single_plr_to_appear "${component_sha}")
    component_push_plr_name="${comp1_plr}"
    comp2_plr=$(wait_for_single_plr_to_appear "${component2_sha}")
    component2_push_plr_name="${comp2_plr}"
}

wait_for_plr_to_complete() {
    wait_for_single_plr_to_complete "${component_push_plr_name}" "${component_name}"
    wait_for_single_plr_to_complete "${component2_push_plr_name}" "${component2_name}"
}

# Find release whose snapshot has exactly 2 components; wait for it to complete.
wait_for_releases() {
    local timeout=300
    local start_time=$(date +%s)
    local release_names=""

    echo "Waiting for release with 2-component snapshot..."
    while [ -z "${release_names}" ]; do
        if [ $(($(date +%s) - start_time)) -ge $timeout ]; then
            log_error "Timeout waiting for Release with 2-component snapshot"
        fi
        sleep 5
        echo -n "."
        local candidates
        candidates=$(kubectl get release -n "${tenant_namespace}" -l "appstudio.openshift.io/build-pipelinerun=${component_push_plr_name}" -o json 2>/dev/null | jq -r '.items[].metadata.name // empty')
        candidates="${candidates} $(kubectl get release -n "${tenant_namespace}" -l "appstudio.openshift.io/build-pipelinerun=${component2_push_plr_name}" -o json 2>/dev/null | jq -r '.items[].metadata.name // empty')"
        for r in $candidates; do
            [ -z "$r" ] && continue
            local snap
            snap=$(kubectl get release "$r" -n "${tenant_namespace}" -o jsonpath='{.spec.snapshot}' 2>/dev/null)
            [ -z "$snap" ] && continue
            local snap_json
            snap_json=$(kubectl get snapshot "$snap" -n "${tenant_namespace}" -o json 2>/dev/null)
            [ -z "$snap_json" ] && continue
            local count
            count=$(jq -r '.spec.components | length' <<< "${snap_json}" 2>/dev/null || echo "0")
            if [ "${count}" = "2" ]; then
                release_names="$r"
                break
            fi
        done
    done
    echo ""
    echo "✅ Found release: $release_names"

    export RELEASE_NAMESPACE="${tenant_namespace}"
    export RELEASE_NAMES="$release_names"
    for release in $release_names; do
        export RELEASE_NAME="${release}"
        "${SUITE_DIR}/../scripts/wait-for-release.sh"
    done
    export RELEASE_NAMES="$release_names"
}
