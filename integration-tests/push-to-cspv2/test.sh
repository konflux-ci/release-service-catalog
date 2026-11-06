#!/usr/bin/env bash
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# Function to verify Release contents
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SUITE_DIR, managed_namespace
verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    local failures=0

    local released_status
    released_status=$(jq -r '([.status.conditions[]? | select(.type=="Released") | .status] | first) // ""' \
        <<< "${release_json}")

    echo "Checking Released=True..."
    if [ "${released_status}" = "True" ]; then
        echo "✅️ Released=True"
    else
        echo "🔴 Released was not True (found: '${released_status}')"
        failures=$((failures+1))
    fi

    local managed_plr_full managed_plr_name
    managed_plr_full=$(jq -r '.status.managedProcessing.pipelineRun // ""' <<< "${release_json}")
    if [ -z "${managed_plr_full}" ]; then
        echo "🔴 managedProcessing.pipelineRun is empty for ${RELEASE_NAME}"
        failures=$((failures+1))
    else
        managed_plr_name=$(basename "${managed_plr_full}")
        echo "Managed PipelineRun: ${managed_plr_name}"

        # Verify the push-to-cspv2 TaskRun ran exactly once and succeeded.
        local taskruns_json push_tr_name push_tr_status push_tr_count
        taskruns_json=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json)
        push_tr_count=$(jq -r \
            '[.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="push-to-cspv2")] | length' \
            <<< "${taskruns_json}")

        if [ "${push_tr_count}" -ne 1 ]; then
            echo "🔴 Expected exactly 1 TaskRun for push-to-cspv2, got ${push_tr_count}"
            failures=$((failures+1))
        else
            push_tr_name=$(jq -r \
                '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="push-to-cspv2") | .metadata.name' \
                <<< "${taskruns_json}")
            push_tr_status=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")

            if [ "${push_tr_status}" != "True" ]; then
                echo "🔴 push-to-cspv2 TaskRun did not succeed: ${push_tr_name} (status=${push_tr_status})"
                failures=$((failures+1))
            else
                echo "✅ push-to-cspv2 TaskRun succeeded: ${push_tr_name}"
            fi

            local push_result expected_checksum actual_checksum
            push_result=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.results[?(@.name=="pushResult")].value}' 2>/dev/null || echo "")
            expected_checksum=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.results[?(@.name=="expectedChecksum")].value}' 2>/dev/null || echo "")
            actual_checksum=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.results[?(@.name=="actualChecksum")].value}' 2>/dev/null || echo "")

            echo "pushResult: ${push_result}"
            echo "expectedChecksum: ${expected_checksum}"
            echo "actualChecksum:   ${actual_checksum}"

            if [ "${push_result}" != "Success" ]; then
                echo "🔴 pushResult was not Success (found: '${push_result}')"
                failures=$((failures+1))
            fi

            if [ -z "${expected_checksum}" ] || [ -z "${actual_checksum}" ]; then
                echo "🔴 expectedChecksum or actualChecksum was empty"
                failures=$((failures+1))
            elif [ "${expected_checksum}" = "${actual_checksum}" ]; then
                echo "✅ actualChecksum matches expectedChecksum (${expected_checksum})"
            else
                echo "🔴 Checksum mismatch: expectedChecksum=${expected_checksum} actualChecksum=${actual_checksum}"
                failures=$((failures+1))
            fi
        fi
    fi

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    fi
    echo "✅ All release checks passed. Success!"
}
