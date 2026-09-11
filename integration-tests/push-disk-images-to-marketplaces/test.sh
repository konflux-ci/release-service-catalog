#!/usr/bin/env bash
# --- Global Script Variables ---
CLEANUP="true"

patch_component_source_before_merge() {
    local secret_value encoded_contents dockerfile
    dockerfile="${SUITE_DIR}/resources/tenant/templates/Dockerfile"
    if [ ! -f "${dockerfile}" ]; then
        echo "🔴 Dockerfile template not found: ${dockerfile}"
        return 1
    fi

    set +x
    secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")
    export GH_TOKEN="${secret_value}"

    encoded_contents=$(base64 -w 0 "${dockerfile}")
    "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${component_repo_name}" \
        "${pr_number}" \
        "Dockerfile" \
        "Build a 1GiB sparse MBR raw disk at /releases/test-disk-image.raw" \
        "${encoded_contents}"
}

# --- Release Verification ---

verify_release_contents() {
    local failures=0

    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    jq '.status' <<< "${release_json}"

    # Verify the managed PipelineRun ran the marketplacesvm-push-disk-images task
    local managed_plr_full
    managed_plr_full=$(jq -r '.status.managedProcessing.pipelineRun // ""' <<< "${release_json}")
    if [ -z "${managed_plr_full}" ]; then
        echo "🔴 managedProcessing.pipelineRun is empty for ${RELEASE_NAME}"
        failures=$((failures+1))
    else
        local managed_plr_name
        managed_plr_name=$(basename "${managed_plr_full}")
        echo "Checking managed PipelineRun ${managed_plr_name} for marketplacesvm-push-disk-images task execution..."

        local push_tr_count
        push_tr_count=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json \
            | jq -r '[.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="marketplacesvm-push-disk-images")] | length')

        if [ "${push_tr_count}" -ne 1 ]; then
            echo "🔴 Expected exactly 1 TaskRun for marketplacesvm-push-disk-images, got ${push_tr_count}"
            failures=$((failures+1))
        else
            local push_tr_name push_tr_status
            push_tr_name=$(kubectl get taskrun -n "${managed_namespace}" \
                -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json \
                | jq -r '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="marketplacesvm-push-disk-images") | .metadata.name')
            push_tr_status=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")

            if [ "${push_tr_status}" != "True" ]; then
                echo "🔴 marketplacesvm-push-disk-images TaskRun did not succeed: ${push_tr_name} (status=${push_tr_status})"
                failures=$((failures+1))
            else
                echo "✅ marketplacesvm-push-disk-images TaskRun succeeded: ${push_tr_name}"

                # Check for any credential validation errors
                if kubectl logs "${push_tr_name}" -n "${managed_namespace}" --all-containers 2>/dev/null \
                        | grep -q "No credential files found"; then
                    echo "🔴 marketplacesvm-push-disk-images TaskRun logged credential error"
                    failures=$((failures+1))
                fi

                # Check for any file extraction errors
                if kubectl logs "${push_tr_name}" -n "${managed_namespace}" --all-containers 2>/dev/null \
                        | grep -q "Source file.*was not found"; then
                    echo "🔴 marketplacesvm-push-disk-images TaskRun logged file extraction error"
                    failures=$((failures+1))
                fi
            fi
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        log_error "Test FAILED with ${failures} failure(s)!"
    fi
    echo "✅ All checks passed."
}
