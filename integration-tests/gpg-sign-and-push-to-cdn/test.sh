#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# --- Snapshot and Release Management ---

wait_for_releases() {
    local snapshot_name
    snapshot_name=$(wait_for_single_component_snapshot)
    if [ -z "$snapshot_name" ]; then
        echo "Could not find single-component snapshot"
        exit 1
    fi

    local release_name="gpg-sign-cdn-${uuid}"

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

    export RELEASE_NAME=${release_name}
    export RELEASE_NAMESPACE=${tenant_namespace}
    "${SUITE_DIR}/../scripts/wait-for-release.sh"

    export RELEASE_NAMES="${release_name}"
}

# --- Release Verification ---

verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
        return 1
    fi

    jq '.status' <<< "${release_json}"

    local failures=0

    local managed_plr_full
    managed_plr_full=$(jq -r '.status.managedProcessing.pipelineRun // ""' <<< "${release_json}")
    if [ -z "${managed_plr_full}" ]; then
        echo "🔴 managedProcessing.pipelineRun is empty for ${RELEASE_NAME}"
        failures=$((failures + 1))
    else
        local managed_plr_name
        managed_plr_name=$(basename "${managed_plr_full}")
        echo "Managed PipelineRun: ${managed_plr_name}"

        local taskruns_json
        taskruns_json=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json)

        # Verify gpg-sign-and-push-to-cdn task ran and succeeded
        local sign_tr_count sign_tr_name sign_tr_status
        sign_tr_count=$(jq -r \
            '[.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="gpg-sign-and-push-to-cdn")] | length' \
            <<< "${taskruns_json}")

        if [ "${sign_tr_count}" -ne 1 ]; then
            echo "🔴 Expected exactly 1 TaskRun for gpg-sign-and-push-to-cdn, got ${sign_tr_count}"
            failures=$((failures + 1))
        else
            sign_tr_name=$(jq -r \
                '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="gpg-sign-and-push-to-cdn") | .metadata.name' \
                <<< "${taskruns_json}")
            sign_tr_status=$(kubectl get taskrun "${sign_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")

            if [ "${sign_tr_status}" != "True" ]; then
                echo "🔴 gpg-sign-and-push-to-cdn TaskRun did not succeed: ${sign_tr_name} (status=${sign_tr_status})"
                failures=$((failures + 1))
            else
                echo "✅ gpg-sign-and-push-to-cdn TaskRun succeeded: ${sign_tr_name}"
            fi
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    fi
    echo "✅ All release checks passed. Success!"
}
