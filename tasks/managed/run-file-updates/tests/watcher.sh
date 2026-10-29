#!/usr/bin/env bash
set -eux

# Patch InternalRequest statuses until the task stops this sidecar.
# The deadline covers trusted-artifact setup plus the configured request timeout
# so discovery cannot end before the task has created its InternalRequests.

PIPELINERUN_UID="${PARAM_PIPELINE_RUN_UID:-}"
REQUEST_TIMEOUT="${PARAM_REQUEST_TIMEOUT:-900}"
SETUP_GRACE_SECONDS=300
DISCOVERY_SECONDS="$((REQUEST_TIMEOUT + SETUP_GRACE_SECONDS))"
END_TIME="$(date -ud "${DISCOVERY_SECONDS} seconds" +%s)"
PARAM_DATA_DIR="${PARAM_DATA_DIR:-}"
PARAM_FILE_UPDATES_PATH="${PARAM_FILE_UPDATES_PATH:-}"
PARAM_JSON_KEY="${PARAM_JSON_KEY:-.spec.data.fileUpdates}"
EXPECTED_IR_COUNT=""
PROCESSED_IRS=""
PATCHED_COUNT=0
PATCH_FILE=""
STOP=0

on_stop() {
    STOP=1
}

discover_expected_count() {
    local updates_file count
    if [[ -n "${EXPECTED_IR_COUNT}" || -z "${PARAM_DATA_DIR}" || -z "${PARAM_FILE_UPDATES_PATH}" ]]; then
        return 0
    fi
    updates_file="${PARAM_DATA_DIR}/${PARAM_FILE_UPDATES_PATH}"
    if [[ ! -f "${updates_file}" ]]; then
        return 0
    fi
    count="$(jq -r "${PARAM_JSON_KEY} | length" "${updates_file}" 2>/dev/null || true)"
    if [[ "${count}" =~ ^[0-9]+$ ]]; then
        EXPECTED_IR_COUNT="${count}"
        echo "Expecting ${EXPECTED_IR_COUNT} InternalRequest(s) from ${updates_file}"
    fi
}

report_results() {
    if [[ -n "${PATCH_FILE}" ]]; then
        rm -f "${PATCH_FILE}"
    fi
    if [[ -z "${EXPECTED_IR_COUNT}" ]]; then
        echo "ERROR: File updates input was not available; patched ${PATCHED_COUNT}" >&2
        exit 1
    fi
    if [[ "${PATCHED_COUNT}" -lt "${EXPECTED_IR_COUNT}" ]]; then
        echo "ERROR: Patched ${PATCHED_COUNT} of ${EXPECTED_IR_COUNT} expected" \
            "InternalRequests before the watcher stopped" >&2
        exit 1
    fi
    echo "IR watcher patched ${PATCHED_COUNT} InternalRequest(s)"
    exit 0
}

trap report_results EXIT
trap on_stop TERM INT

echo "Starting IR status watcher for pipelineRun uid: ${PIPELINERUN_UID}"
echo "Watching until the task finishes or ${DISCOVERY_SECONDS}s elapses"

while [[ "${STOP}" -eq 0 && "$(date +%s)" -lt "${END_TIME}" ]]; do
    discover_expected_count
    # Get all InternalRequests for this pipeline run that don't have a status yet
    IRS="$(kubectl get internalrequest -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINERUN_UID}" \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.results.buildState}{"\n"}{end}' 2>/dev/null || true)"

    while IFS=' ' read -r NAME STATE; do
        if [[ -z "${NAME}" ]]; then
            continue
        fi

        # Skip if already processed
        if [[ "${PROCESSED_IRS}" == *"${NAME}"* ]]; then
            continue
        fi

        # Skip if already has a state
        if [[ -n "${STATE}" ]]; then
            PROCESSED_IRS="${PROCESSED_IRS} ${NAME}"
            continue
        fi

        echo "Found new InternalRequest: ${NAME}"

        # Check if this IR should fail based on ref parameter
        REF="$(kubectl get internalrequest "${NAME}" -o jsonpath='{.spec.params.ref}' 2>/dev/null || true)"

        PATCH_FILE="$(mktemp)"
        mockPipelineRunName="$(openssl rand -hex 12)"
        mockTaskRunName="${mockPipelineRunName}-tr"

        if [[ "${REF}" == "fail"* ]]; then
            echo "Setting status of ${NAME} to Failed"
            build_state="Failed"
            json_build_info='{"error":"unknown error","str":"unknown error"}'
        else
            echo "Setting status of ${NAME} to Succeeded"
            build_state="Succeeded"
            json_build_info='{"merge_request":"https://g/r/-/merge_requests/18"}'
        fi

        jq -n \
            --arg pipelineRunName "${mockPipelineRunName}" \
            --arg taskRunName "${mockTaskRunName}" \
            --arg buildState "${build_state}" \
            --arg jsonBuildInfo "${json_build_info}" \
            '{
              status: {
                results: {
                  internalRequestPipelineRunName: $pipelineRunName,
                  internalRequestTaskRunName: $taskRunName,
                  buildState: $buildState,
                  jsonBuildInfo: $jsonBuildInfo
                }
              }
            }' > "${PATCH_FILE}"

        # Wait a bit to simulate processing time
        sleep 2

        # Recreate the patch payload on the next poll when this fails. Only a
        # successful patch is recorded, so a later iteration can retry.
        patch_status=0
        kubectl patch internalrequest "${NAME}" --type=merge --subresource status \
            --patch-file "${PATCH_FILE}" || patch_status=$?
        rm -f "${PATCH_FILE}"
        PATCH_FILE=""

        if [[ "${patch_status}" -eq 0 ]]; then
            PROCESSED_IRS="${PROCESSED_IRS} ${NAME}"
            PATCHED_COUNT="$((PATCHED_COUNT + 1))"
            echo "Patched InternalRequest: ${NAME}"
        else
            echo "ERROR: Failed to patch InternalRequest ${NAME} (exit ${patch_status}); will retry" >&2
        fi
    done <<< "${IRS}"

    sleep 2 || true
done
