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

wait_for_single_component_initialization() {
    local comp_name=$1
    local max_attempts=90
    local attempt=1
    local component_annotations=""

    while [ $attempt -le $max_attempts ]; do
        component_annotations=$(kubectl get component/"${comp_name}" -n "${tenant_namespace}" -ojson 2>/dev/null | \
            jq -r --arg k "build.appstudio.openshift.io/status" '.metadata.annotations[$k] // ""' 2>/dev/null) || component_annotations=""

        if [ -n "${component_annotations}" ]; then
            component_pr=$(jq -r '.pac."merge-url" // ""' <<< "${component_annotations}")
            if [ -n "${component_pr}" ]; then
                echo "✅ Component ${comp_name} initialized"
                pr_number=$(cut -f7 -d/ <<< "${component_pr}")
                return 0
            fi
        fi
        if [ $((attempt % 6)) -eq 0 ]; then
            echo "   Still waiting for ${comp_name} (attempt ${attempt}/${max_attempts})..."
        fi
        attempt=$((attempt + 1))
        sleep 10
    done

    # Debug: dump component state on timeout so we can see why PaC didn't set merge-url
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DEBUG: Component initialization timeout for ${comp_name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ! kubectl get component/"${comp_name}" -n "${tenant_namespace}" &>/dev/null; then
        echo "  Component does not exist in ${tenant_namespace}."
        echo "  Check: kubectl get component -n ${tenant_namespace}"
    else
        echo "  Component exists. Annotation build.appstudio.openshift.io/status:"
        local status_annot
        status_annot=$(kubectl get component/"${comp_name}" -n "${tenant_namespace}" -o jsonpath='{.metadata.annotations.build\.appstudio\.openshift\.io/status}' 2>/dev/null)
        if [ -z "${status_annot}" ]; then
            echo "  (missing - PaC has not set it yet)"
        else
            echo "${status_annot}" | jq '.' 2>/dev/null || echo "${status_annot}"
        fi
        echo ""
        echo "  Spec (repo/branch):"
        kubectl get component/"${comp_name}" -n "${tenant_namespace}" -o json 2>/dev/null | jq -r '.spec' 2>/dev/null || \
            kubectl get component/"${comp_name}" -n "${tenant_namespace}" -o yaml 2>/dev/null | grep -A 20 '^spec:'
        echo ""
        echo "  To inspect full resource:"
        echo "    kubectl get component ${comp_name} -n ${tenant_namespace} -o yaml"
        echo "  To check Pipelines as Code / build controller logs:"
        echo "    kubectl logs -n openshift-pipelines -l app.kubernetes.io/name=pipelines-as-code --tail=100"
        echo "    kubectl logs -n build-service -l app.kubernetes.io/name=build-service --tail=100"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_error "Component ${comp_name} failed to initialize after ${max_attempts} attempts"
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

merge_single_component_pr() {
    local pr_num=$1
    local repo_name=$2
    local commit_message="e2e test"
    local merge_result
    merge_result=$(curl -L -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${repo_name}/pulls/${pr_num}/merge" \
        -d "{\"commit_title\":\"e2e test\",\"commit_message\":\"${commit_message}\"}" --silent --show-error --fail-with-body)
    SHA=$(jq -r '.sha' <<< "${merge_result}")
}

wait_for_single_plr_to_appear() {
    local sha=$1
    local timeout=300
    local start_time=$(date +%s)
    local found_plr_name=""

    # Status output goes to stderr so command substitution only captures the PLR name
    echo -n "Waiting for PipelineRun for SHA ${sha}..." >&2
    while [ -z "$found_plr_name" ]; do
        if [ $(($(date +%s) - start_time)) -ge $timeout ]; then
            echo "" >&2
            log_error "Timeout waiting for PipelineRun for SHA ${sha}"
        fi
        sleep 5
        echo -n "." >&2
        found_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$sha" -n "${tenant_namespace}" --no-headers 2>/dev/null | { grep "Running" || true; } | awk '{print $1}')
    done
    echo "" >&2
    echo "✅ Found PipelineRun: ${found_plr_name}" >&2
    echo "${found_plr_name}"
}

wait_for_plr_to_appear() {
    echo "Waiting for PipelineRuns for both components..."
    comp1_plr=$(wait_for_single_plr_to_appear "${component_sha}")
    component_push_plr_name="${comp1_plr}"
    comp2_plr=$(wait_for_single_plr_to_appear "${component2_sha}")
    component2_push_plr_name="${comp2_plr}"
}

wait_for_single_plr_to_complete() {
    local plr_name=$1
    local timeout=1800
    local start_time=$(date +%s)
    local status=""

    echo "Waiting for PipelineRun ${plr_name} to complete..."
    while true; do
        if [ $(($(date +%s) - start_time)) -ge $timeout ]; then
            log_error "Timeout waiting for PipelineRun ${plr_name}"
        fi
        sleep 5
        status=$(kubectl get pipelinerun "${plr_name}" -n "${tenant_namespace}" \
            -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null) || status=""
        if [ "${status}" = "True" ]; then
            echo "✅ ${plr_name} completed"
            break
        elif [ "${status}" = "False" ]; then
            echo "❌ ${plr_name} failed"
            exit 1
        fi
        # status is empty (PLR not yet created/found) or "Unknown" (still running) — keep polling
    done
}

wait_for_plr_to_complete() {
    wait_for_single_plr_to_complete "${component_push_plr_name}"
    wait_for_single_plr_to_complete "${component2_push_plr_name}"
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
