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

    # CGW state is printed as diagnostic info, not asserted.
    # Hard assertions are not practical because the test cluster
    # may not have network access to the CGW API.
    echo ""
    echo "CGW state:"
    _print_cgw_state

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    fi
    echo "✅ All release checks passed. Success!"
}

_print_cgw_state() {
    local cgw_secret_name="cgw-service-account-stage-secret"
    local cgw_hostname="https://developers.qa.redhat.com/content-gateway/rest/admin"
    local cgw_product_name="Konflux Release E2E test product"
    local cgw_product_version="1.0"
    local cgw_user cgw_pass

    local _xtrace_on=0
    case $- in *x*) _xtrace_on=1 ;; esac
    trap '(( _xtrace_on )) && set -x || { set +x; } 2>/dev/null' RETURN

    { set +x; } 2>/dev/null
    cgw_user=$(kubectl get secret "${cgw_secret_name}" -n "${managed_namespace}" \
        -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
    cgw_pass=$(kubectl get secret "${cgw_secret_name}" -n "${managed_namespace}" \
        -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
    if [ -z "${cgw_user}" ] || [ -z "${cgw_pass}" ]; then
        echo "  Could not retrieve CGW credentials from ${cgw_secret_name}, skipping CGW state report"
        return 0
    fi
    (( _xtrace_on )) && set -x || { set +x; } 2>/dev/null

    local proxy_args=()
    if [[ "${cgw_hostname}" == *"developers.qa.redhat.com"* ]]; then
        proxy_args=(--proxy "http://squid.corp.redhat.com:3128")
    fi

    _cgw_get() {
        local _url="$1" _out="$2" _code
        { set +x; } 2>/dev/null
        _code=$(curl --retry 3 -L -s -w "%{http_code}" "${proxy_args[@]}" \
            -u "${cgw_user}:${cgw_pass}" -H "Accept: application/json" \
            -o "${_out}" "${_url}" 2>/dev/null || true)
        (( _xtrace_on )) && set -x || { set +x; } 2>/dev/null
        printf '%s' "${_code}"
    }

    local products_file versions_file cgw_files_file product_id http_code
    products_file=$(mktemp)
    versions_file=""
    cgw_files_file=""
    trap 'rm -f "${products_file}" "${versions_file}" "${cgw_files_file}";
          (( _xtrace_on )) && set -x || { set +x; } 2>/dev/null' RETURN

    http_code=$(_cgw_get "${cgw_hostname}/products" "${products_file}")
    if [ "${http_code}" != "200" ]; then
        echo "  CGW products endpoint returned HTTP ${http_code:-network error}, skipping CGW state report"
        return 0
    fi
    product_id=$(jq -r --arg name "${cgw_product_name}" \
        '.[] | select(.name == $name) | .id' "${products_file}" 2>/dev/null | head -1)
    if [ -z "${product_id}" ]; then
        echo "  CGW product '${cgw_product_name}' not found, skipping CGW state report"
        return 0
    fi

    versions_file=$(mktemp)
    local version_id
    http_code=$(_cgw_get "${cgw_hostname}/products/${product_id}/versions" "${versions_file}")
    if [ "${http_code}" != "200" ]; then
        echo "  CGW versions endpoint returned HTTP ${http_code:-network error}, skipping CGW state report"
        return 0
    fi
    version_id=$(jq -r --arg name "${cgw_product_version}" \
        '.[] | select(.versionName == $name) | .id' "${versions_file}" 2>/dev/null | head -1)
    if [ -z "${version_id}" ]; then
        echo "  CGW version '${cgw_product_version}' not found, skipping CGW state report"
        return 0
    fi

    cgw_files_file=$(mktemp)
    http_code=$(_cgw_get \
        "${cgw_hostname}/products/${product_id}/versions/${version_id}/files" \
        "${cgw_files_file}")
    if [ "${http_code}" != "200" ]; then
        echo "  CGW files endpoint returned HTTP ${http_code:-network error}, skipping CGW state report"
        return 0
    fi

    echo "  CGW files for ${cgw_product_name} v${cgw_product_version}:"
    jq -r '.[] | "    \(.label): \(.shortURL)"' "${cgw_files_file}"
}
