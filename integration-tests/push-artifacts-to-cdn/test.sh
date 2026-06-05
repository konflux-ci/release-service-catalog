#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Tell the framework to manage two components: component (Pulp+CGW) and component2 (CGW only).
PTSV_COMPONENTS="component component2"

# --- Snapshot and Release Management ---

wait_for_releases() {
    local snapshot_name
    snapshot_name=$(wait_for_multi_component_snapshot)
    if [ -z "$snapshot_name" ]; then
        echo "Could not find multi-component snapshot"
        exit 1
    fi

    local release_name="push-artifacts-cdn-${uuid}"

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

        # Verify the push-artifacts-to-cdn TaskRun ran exactly once and succeeded.
        local taskruns_json push_tr_name push_tr_status push_tr_count
        taskruns_json=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json)
        push_tr_count=$(jq -r '[.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="push-artifacts-to-cdn")] | length' \
            <<< "${taskruns_json}")

        if [ "${push_tr_count}" -ne 1 ]; then
            echo "🔴 Expected exactly 1 TaskRun for push-artifacts-to-cdn, got ${push_tr_count}"
            failures=$((failures + 1))
        else
            push_tr_name=$(jq -r '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="push-artifacts-to-cdn") | .metadata.name' \
                <<< "${taskruns_json}")
            push_tr_status=$(kubectl get taskrun "${push_tr_name}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")

            if [ "${push_tr_status}" != "True" ]; then
                echo "🔴 push-artifacts-to-cdn TaskRun did not succeed: ${push_tr_name} (status=${push_tr_status})"
                failures=$((failures + 1))
            else
                echo "✅ push-artifacts-to-cdn TaskRun succeeded: ${push_tr_name}"
            fi
        fi
    fi

    # CGW and Pulp are printed as diagnostic state, not asserted.
    # See README for why hard assertions are not practical here.
    echo ""
    echo "CGW state:"
    _print_cgw_state

    echo ""
    echo "Pulp state:"
    _print_pulp_state

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    fi
    echo "✅ All release checks passed. Success!"
}

# Print the current file list for this test's CGW product/version.
# Informational only — not a pass/fail assertion.
_print_cgw_state() {
    local cgw_secret_name="cgw-service-account-stage-secret"
    local cgw_hostname="https://developers.qa.redhat.com/content-gateway/rest/admin"
    local cgw_product_name="Konflux Release E2E test product"
    local cgw_product_version="1.0"
    local cgw_user cgw_pass

    # Capture and restore xtrace state on all exit paths; keep credentials out of the trace.
    local _xtrace_on=0
    case $- in *x*) _xtrace_on=1 ;; esac
    trap '(( _xtrace_on )) && set -x || { set +x; } 2>/dev/null' RETURN

    { set +x; } 2>/dev/null
    cgw_user=$(kubectl get secret "${cgw_secret_name}" -n "${managed_namespace}" \
        -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
    cgw_pass=$(kubectl get secret "${cgw_secret_name}" -n "${managed_namespace}" \
        -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
    if [ -z "${cgw_user}" ] || [ -z "${cgw_pass}" ]; then
        echo "⚠️ Could not retrieve CGW credentials from ${cgw_secret_name}, skipping CGW state report"
        return 0
    fi
    (( _xtrace_on )) && set -x || { set +x; } 2>/dev/null

    local proxy_args=()
    if [[ "${cgw_hostname}" == *"developers.qa.redhat.com"* ]]; then
        proxy_args=(--proxy "http://squid.corp.redhat.com:3128")
    fi

    # Helper: make one authenticated CGW GET request, hiding credentials from the trace.
    # Usage: _cgw_get <url> <outfile>; returns the HTTP status code.
    _cgw_get() {
        local _url="$1" _out="$2" _code
        { set +x; } 2>/dev/null
        _code=$(curl --retry 3 -L -s -w "%{http_code}" "${proxy_args[@]}" \
            -u "${cgw_user}:${cgw_pass}" -H "Accept: application/json" \
            -o "${_out}" "${_url}" 2>/dev/null)
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
        echo "⚠️ CGW products endpoint returned HTTP ${http_code}, skipping CGW state report"
        return 0
    fi
    product_id=$(jq -r --arg name "${cgw_product_name}" \
        '.[] | select(.name == $name) | .id' "${products_file}" 2>/dev/null | head -1)
    if [ -z "${product_id}" ]; then
        echo "⚠️ CGW product '${cgw_product_name}' not found, skipping CGW state report"
        return 0
    fi

    versions_file=$(mktemp)
    local version_id
    http_code=$(_cgw_get "${cgw_hostname}/products/${product_id}/versions" "${versions_file}")
    if [ "${http_code}" != "200" ]; then
        echo "⚠️ CGW versions endpoint returned HTTP ${http_code}, skipping CGW state report"
        return 0
    fi
    version_id=$(jq -r --arg name "${cgw_product_version}" \
        '.[] | select(.versionName == $name) | .id' "${versions_file}" 2>/dev/null | head -1)
    if [ -z "${version_id}" ]; then
        echo "⚠️ CGW version '${cgw_product_version}' not found, skipping CGW state report"
        return 0
    fi

    cgw_files_file=$(mktemp)
    http_code=$(_cgw_get \
        "${cgw_hostname}/products/${product_id}/versions/${version_id}/files" \
        "${cgw_files_file}")
    if [ "${http_code}" != "200" ]; then
        echo "⚠️ CGW files endpoint returned HTTP ${http_code}, skipping CGW state report"
        return 0
    fi

    echo "CGW files for ${cgw_product_name} v${cgw_product_version}:"
    jq -r '.[] | "  \(.label): \(.shortURL)"' "${cgw_files_file}"
}

# Print the current e2e file list from the Pulp stage repository.
# Informational only — not a pass/fail assertion.
_print_pulp_state() {
    local pulp_secret_name="rhsm-pulp-stage-secret"
    local pulp_repo="konflux-release-e2e-1_DOT_0-for-rhel-10-x86_64-files"
    local pulp_base_url pulp_cert pulp_key

    # Capture and restore xtrace state on all exit paths; keep credentials out of the trace.
    local _xtrace_on=0
    case $- in *x*) _xtrace_on=1 ;; esac
    trap '(( _xtrace_on )) && set -x || { set +x; } 2>/dev/null' RETURN

    { set +x; } 2>/dev/null
    local pulp_secret_json
    pulp_secret_json=$(kubectl get secret "${pulp_secret_name}" -n "${managed_namespace}" \
        -o json 2>/dev/null || echo "")
    pulp_base_url=$(jq -r '.data.pulp_url // empty' <<< "${pulp_secret_json}" 2>/dev/null | base64 -d || echo "")
    pulp_base_url="${pulp_base_url%/}"
    pulp_cert=$(jq -r '.data["konflux-release-rhsm-pulp.crt"] // empty' <<< "${pulp_secret_json}" 2>/dev/null | base64 -d || echo "")
    pulp_key=$(jq -r '.data["konflux-release-rhsm-pulp.key"] // empty' <<< "${pulp_secret_json}" 2>/dev/null | base64 -d || echo "")

    if [ -z "${pulp_base_url}" ] || [ -z "${pulp_cert}" ] || [ -z "${pulp_key}" ]; then
        echo "⚠️ Could not retrieve Pulp credentials from ${pulp_secret_name}, skipping Pulp state report"
        return 0
    fi

    # Write credentials to temp files and make the API call, all under set +x so
    # neither the cert/key content nor the file paths appear in the trace while the
    # files exist on disk.
    local pulp_cert_file pulp_key_file pulp_response_file
    pulp_cert_file=$(mktemp --suffix=.crt)
    pulp_key_file=$(mktemp --suffix=.key)
    pulp_response_file=$(mktemp)
    trap 'rm -f "${pulp_cert_file}" "${pulp_key_file}" "${pulp_response_file}";
          (( _xtrace_on )) && set -x || { set +x; } 2>/dev/null' RETURN
    printf '%s' "${pulp_cert}" > "${pulp_cert_file}"
    printf '%s' "${pulp_key}" > "${pulp_key_file}"
    chmod 600 "${pulp_key_file}"
    local http_code
    http_code=$(curl --retry 3 -L -s -w "%{http_code}" \
        --cert "${pulp_cert_file}" --key "${pulp_key_file}" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d '{"criteria": {"type_ids": ["iso"]}}' \
        -o "${pulp_response_file}" \
        "${pulp_base_url}/pulp/api/v2/repositories/${pulp_repo}/search/units/" 2>/dev/null)

    if [ "${http_code}" != "200" ]; then
        echo "⚠️ Pulp API returned HTTP ${http_code}, skipping Pulp state report"
        return 0
    fi

    echo "Pulp files in ${pulp_repo} matching e2e-cdn-comp1:"
    jq -r '.[]? | select(.metadata.name | test("e2e-cdn-comp1-1\\.0-"))
        | "  \(.metadata.name) (updated: \(.updated[:19]))"' \
        "${pulp_response_file}" 2>/dev/null
}
