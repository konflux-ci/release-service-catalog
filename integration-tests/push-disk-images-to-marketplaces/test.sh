#!/usr/bin/env bash
#
# test.sh - Multi-component e2e for push-disk-images-to-marketplaces.
#
# Two Konflux Components share one Application. After both builds complete,
# this suite finds the multi-component Snapshot and creates a Release so
# marketplacesvm-push-disk-images processes both disk images in one run.
# Framework multi-component lifecycle is driven by PTSV_COMPONENTS in test.env.
#
# --- Global Script Variables ---
CLEANUP="true"

wait_for_releases() {
    local snapshot_name release_name
    snapshot_name=$(wait_for_multi_component_snapshot)
    if [ -z "${snapshot_name}" ]; then
        echo "Could not find multi-component snapshot"
        exit 1
    fi

    release_name="push-disk-images-marketplaces-multi-${uuid}"

    cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${release_name}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-run-uuid: "${uuid}"
spec:
  snapshot: ${snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    export RELEASE_NAME="${release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    "${SUITE_DIR}/../scripts/wait-for-release.sh"
    export RELEASE_NAMES="${release_name}"
}

patch_component_source_before_merge() {
    local secret_value encoded_contents dockerfile
    local xtrace_was_on=0
    dockerfile="${SUITE_DIR}/resources/tenant/templates/Dockerfile"
    if [ ! -f "${dockerfile}" ]; then
        echo "🔴 Dockerfile template not found: ${dockerfile}"
        return 1
    fi

    [[ $- == *x* ]] && xtrace_was_on=1
    set +x
    trap 'unset secret_value; if [[ "${xtrace_was_on}" -eq 1 ]]; then set -x; fi; trap - RETURN' RETURN

    secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
        "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")
    if [ -z "${secret_value}" ] || [ "${secret_value}" = "null" ]; then
        echo "🔴 PaC token not found in tenant secrets (pipelines-as-code-secret-*)"
        return 1
    fi

    encoded_contents="$(base64 -w 0 "${dockerfile}")"
    if [ -z "${component_repo_name}" ] || [ -z "${pr_number}" ]; then
        echo "🔴 component_repo_name or pr_number is not set; cannot update the component pull request"
        return 1
    fi
    GH_TOKEN="${secret_value}" "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${component_repo_name}" \
        "${pr_number}" \
        "Dockerfile" \
        "Build a 1GiB sparse MBR raw disk at /releases/test-disk-image.raw" \
        "${encoded_contents}" || return 1
}

# --- Release Verification ---

verify_release_contents() {
    local failures=0

    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    jq '.status' <<< "${release_json}"

    local snapshot_name snapshot_json snapshot_count
    snapshot_name=$(jq -r '.spec.snapshot // ""' <<< "${release_json}")
    if [ -z "${snapshot_name}" ]; then
        echo "🔴 Release spec.snapshot is empty"
        failures=$((failures+1))
    else
        snapshot_json=$(kubectl get snapshot/"${snapshot_name}" -n "${RELEASE_NAMESPACE}" -ojson)
        snapshot_count=$(jq '.spec.components | length' <<< "${snapshot_json}")
        echo "Snapshot ${snapshot_name} has ${snapshot_count} component(s)"
        if [ "${snapshot_count}" -ne 2 ]; then
            echo "🔴 Expected 2 snapshot components for multi-batch marketplace push, got ${snapshot_count}"
            failures=$((failures+1))
        else
            local snapshot_names missing_snapshot_component=false
            snapshot_names=$(jq -r '.spec.components[].name' <<< "${snapshot_json}")
            if ! grep -Fxq "${component_name}" <<< "${snapshot_names}"; then
                echo "🔴 Snapshot missing component ${component_name}"
                failures=$((failures+1))
                missing_snapshot_component=true
            fi
            if ! grep -Fxq "${component2_name}" <<< "${snapshot_names}"; then
                echo "🔴 Snapshot missing component ${component2_name}"
                failures=$((failures+1))
                missing_snapshot_component=true
            fi
            if [ "${missing_snapshot_component}" = false ]; then
                echo "✅ Snapshot contains ${component_name} and ${component2_name}"
            fi
        fi
    fi

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
            local push_tr_name push_tr_json push_tr_status
            local push_result_status push_result_message
            push_tr_name="$(kubectl get taskrun -n "${managed_namespace}" \
                -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json \
                | jq -r '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="marketplacesvm-push-disk-images") | .metadata.name')"
            push_tr_json="$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" -o json)"
            push_tr_status="$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status // empty' \
                <<< "${push_tr_json}")"
            push_result_status="$(jq -r --arg name "status" \
                '.status.results[]? | select(.name==$name) | .value // empty' <<< "${push_tr_json}")"
            push_result_message="$(jq -r --arg name "message" \
                '.status.results[]? | select(.name==$name) | .value // empty' <<< "${push_tr_json}")"

            if [ "${push_tr_status}" != "True" ]; then
                echo "🔴 marketplacesvm-push-disk-images TaskRun did not succeed: ${push_tr_name} (status=${push_tr_status})"
                echo "   task result status=${push_result_status} message=${push_result_message}"
                failures=$((failures+1))
            elif [ -z "${push_result_status}" ] || [ "${push_result_status}" != "Success" ]; then
                echo "🔴 marketplacesvm-push-disk-images TaskRun result status is '${push_result_status}' (expected Success)"
                echo "   TaskRun: ${push_tr_name}"
                echo "   message: ${push_result_message}"
                failures=$((failures+1))
            else
                echo "✅ marketplacesvm-push-disk-images TaskRun succeeded: ${push_tr_name}"

                local push_logs
                if ! push_logs="$(tkn taskrun logs "${push_tr_name}" -n "${managed_namespace}")"; then
                    echo "🔴 Failed to retrieve logs for TaskRun ${push_tr_name}"
                    failures=$((failures+1))
                elif [ -z "${push_logs}" ]; then
                    echo "🔴 TaskRun ${push_tr_name} logs are empty"
                    failures=$((failures+1))
                else
                    if ! grep -Fq "${component_name}" <<< "${push_logs}"; then
                        echo "🔴 marketplacesvm-push-disk-images logs missing ${component_name}"
                        failures=$((failures+1))
                    fi
                    if ! grep -Fq "${component2_name}" <<< "${push_logs}"; then
                        echo "🔴 marketplacesvm-push-disk-images logs missing ${component2_name}"
                        failures=$((failures+1))
                    fi

                    # Check for any credential validation errors
                    if grep -q "No credential files found" <<< "${push_logs}"; then
                        echo "🔴 marketplacesvm-push-disk-images TaskRun logged credential error"
                        failures=$((failures+1))
                    fi

                    # Check for any file extraction errors
                    if grep -q "Source file.*was not found" <<< "${push_logs}"; then
                        echo "🔴 marketplacesvm-push-disk-images TaskRun logged file extraction error"
                        failures=$((failures+1))
                    fi
                fi
            fi
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        log_error "Test FAILED with ${failures} failure(s)!"
    fi
    echo "✅ All checks passed."
}
