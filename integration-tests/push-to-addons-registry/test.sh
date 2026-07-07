# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"
# GitHub API curl retries (override in CI/local: export GITHUB_API_CURL_RETRY=5)
GITHUB_API_CURL_RETRY="${GITHUB_API_CURL_RETRY:-3}"

# GET a GitHub API JSON resource; prints the response body on success, returns 1 on curl/HTTP error.
# Args: token url detail_msg fallback_msg (used when curl fails, with/without .message from body)
github_api_get_json() {
  local token="$1"
  local url="$2"
  local detail_msg="$3"
  local fallback_msg="$4"
  local response api_msg
  local xtrace_was_on=0
  case $- in
    *x*) xtrace_was_on=1 ;;
  esac
  if [ "${xtrace_was_on}" -eq 1 ]; then
    set +x
  fi

  if ! response=$(curl --retry "${GITHUB_API_CURL_RETRY}" -s --fail-with-body \
    -H "Authorization: token ${token}" \
    "${url}"); then
    if [ "${xtrace_was_on}" -eq 1 ]; then
      set -x
    fi
    if api_msg=$(jq -r '.message // empty' <<< "${response}" 2>/dev/null) && [ -n "${api_msg}" ]; then
      echo "❌ error: ${detail_msg}: ${api_msg}" >&2
    else
      echo "❌ error: ${fallback_msg}" >&2
    fi
    return 1
  fi
  if [ "${xtrace_was_on}" -eq 1 ]; then
    set -x
  fi
  echo "${response}"
}

patch_component_source_before_merge() {
  # CI often runs scripts under xtrace (bash -x). Disable tracing only while handling tokens.
  local xtrace_was_on=0
  case $- in
    *x*) xtrace_was_on=1 ;;
  esac
  if [ "${xtrace_was_on}" -eq 1 ]; then
    set +x
  fi

  trap 'unset secret_value 2>/dev/null; if [ "${xtrace_was_on}" -eq 1 ]; then set -x; fi' RETURN

  echo "Patching component source BEFORE MERGE to ensure multi-arch build..."

  # PaC GitHub token: do not export — scoped env only for the helper that requires GH_TOKEN.
  # Vault file uses ${component_name} placeholders; envsubst runs at kubectl apply, not on disk.
  local secret_value
  secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
    "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml" | head -n 1)
  while [[ "${secret_value}" == *$'\n' ]]; do
    secret_value="${secret_value%$'\n'}"
  done

  if [ -z "${secret_value}" ] || [ "${secret_value}" = "null" ]; then
    log_error "PaC token not found in tenant secrets (pipelines-as-code-secret-*)"
  fi

  local file_names=(
    ".tekton/${component_name}-pull-request.yaml"
    ".tekton/${component_name}-push.yaml"
  )
  local head_sha pr_response
  pr_response=$(github_api_get_json "${secret_value}" \
    "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}" \
    "GitHub API error fetching PR ${pr_number}" \
    "failed to fetch PR ${pr_number} from ${component_repo_name} (check PaC token and repo access)") || exit 1
  head_sha=$(jq -r -e '.head.sha' <<< "${pr_response}") || {
    log_error "missing or invalid .head.sha in PR ${pr_number} response"
  }

  for file_name in "${file_names[@]}"; do
    local decoded_contents encoded_contents
    local contents_response encoded_content_field
    echo "Patching ${file_name}..."

    contents_response=$(github_api_get_json "${secret_value}" \
      "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}" \
      "GitHub API error fetching ${file_name}" \
      "failed to fetch ${file_name} at ref ${head_sha} from ${component_repo_name}") || exit 1

    encoded_content_field=$(jq -r -e '.content' <<< "${contents_response}") || {
      log_error "missing or invalid .content for ${file_name} in PR ${pr_number}"
    }
    if ! decoded_contents=$(base64 -d <<< "${encoded_content_field}"); then
      log_error "failed to base64-decode ${file_name} from PR ${pr_number}"
    fi
    if [ -z "${decoded_contents}" ]; then
      log_error "decoded contents for ${file_name} are empty"
    fi

    encoded_contents=$(
      set -eo pipefail
      work_dir=$(mktemp -d)
      trap 'rm -rf "${work_dir}"' EXIT
      nopath_file_name=$(basename "${file_name}")
      echo "${decoded_contents}" > "${work_dir}/${nopath_file_name}"

      # Ensure linux/amd64 + linux/arm64 are present.
      if yq -e '(.spec.params[]? | select(.name == "build-platforms") | .value | type) == "!!seq"' \
        "${work_dir}/${nopath_file_name}" >/dev/null 2>&1; then
        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) |= ([.[] | select(. != "linux/arm64")] + ["linux/arm64"])' \
          "${work_dir}/${nopath_file_name}"
        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) |= ([.[] | select(. != "linux/amd64")] + ["linux/amd64"])' \
          "${work_dir}/${nopath_file_name}"
      elif yq -e '(.spec.params[]? | select(.name == "build-platforms"))' \
        "${work_dir}/${nopath_file_name}" >/dev/null 2>&1; then
        yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) = ["linux/amd64", "linux/arm64"]' \
          "${work_dir}/${nopath_file_name}"
      else
        yq -i '.spec.params += [{"name": "build-platforms", "value": ["linux/amd64", "linux/arm64"]}]' \
          "${work_dir}/${nopath_file_name}"
      fi

      base64 -w 0 < "${work_dir}/${nopath_file_name}"
    ) || {
      log_error "failed to patch ${file_name} for multi-arch build"
    }

    GH_TOKEN="${secret_value}" "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
      "${component_repo_name}" \
      "${pr_number}" \
      "${file_name}" \
      "Update PaC templates for multi-arch build" \
      "${encoded_contents}" || log_error "failed to update ${file_name} in PR ${pr_number}"
  done

  echo "✅️ Successfully patched component PaC templates for multi-arch."
}

# --- Snapshot and Release Management ---

wait_for_releases() {
    local snapshot_name
    snapshot_name=$(wait_for_multi_component_snapshot)
    if [ -z "${snapshot_name}" ]; then
        echo "Could not find multi-component snapshot"
        exit 1
    fi

    local release_name="push-addons-multi-${uuid}"

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
    fi

    local failures=0

    local released_status
    released_status=$(jq -r '([.status.conditions[]? | select(.type=="Released") | .status] | first) // ""' <<< "${release_json}")

    echo "Checking Released=True..."
    if [ "${released_status}" = "True" ]; then
        echo "✅️ Released=True"
    else
        echo "🔴 Released was not True (found: '${released_status}')"
        failures=$((failures+1))
    fi

    echo ""
    echo "Checking for 2 image entries with distinct URLs and shasums..."

    local image_count
    image_count=$(jq -r '.status.artifacts.images | length' <<< "${release_json}")

    echo "Found ${image_count} image entries in status.artifacts.images"
    if [ "${image_count}" -ge 2 ]; then
        echo "✅️ Found ${image_count} image entries (expected at least 2)"
    else
        echo "🔴 Found only ${image_count} image entries, expected at least 2"
        failures=$((failures+1))
    fi

    local image0_url image0_shasum image1_url image1_shasum
    image0_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image0_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")
    image1_url=$(jq -r '.status.artifacts.images[1]?.urls[0] // ""' <<< "${release_json}")
    image1_shasum=$(jq -r '.status.artifacts.images[1]?.shasum // ""' <<< "${release_json}")

    echo "Image 0: url=${image0_url}, shasum=${image0_shasum}"
    echo "Image 1: url=${image1_url}, shasum=${image1_shasum}"

    if [ -n "${image0_url}" ] && [ -n "${image1_url}" ]; then
        echo "✅️ Both image URLs are non-empty"
    else
        echo "🔴 One or both image URLs are empty"
        failures=$((failures+1))
    fi

    if [ -n "${image0_shasum}" ] && [ -n "${image1_shasum}" ]; then
        echo "✅️ Both image shasums are non-empty"
    else
        echo "🔴 One or both image shasums are empty"
        failures=$((failures+1))
    fi

    if [ "${image0_url}" != "${image1_url}" ]; then
        echo "✅️ Image URLs are distinct"
    else
        echo "🔴 Image URLs are identical: ${image0_url}"
        failures=$((failures+1))
    fi

    if [ "${image0_shasum}" != "${image1_shasum}" ]; then
        echo "✅️ Image shasums are distinct"
    else
        echo "🔴 Image shasums are identical: ${image0_shasum}"
        failures=$((failures+1))
    fi

    echo ""
    echo "Verifying arches and skopeo pullability for each image..."

    for i in 0 1; do
        local img_url img_shasum img_arches
        img_url=$(jq -r --argjson idx "$i" '.status.artifacts.images[$idx]?.urls[0] // ""' <<< "${release_json}")
        img_shasum=$(jq -r --argjson idx "$i" '.status.artifacts.images[$idx]?.shasum // ""' <<< "${release_json}")
        img_arches=$(jq -r --argjson idx "$i" '(.status.artifacts.images[$idx]?.arches // [])
          | map((tostring | split("/") | .[-1]))
          | unique
          | join(" ")' <<< "${release_json}")

        echo ""
        echo "Image ${i}: url=${img_url}, shasum=${img_shasum}, arches=${img_arches}"

        if [ -z "${img_url}" ] || [ -z "${img_shasum}" ]; then
            echo "🔴 Image ${i}: missing url or shasum, skipping remaining checks"
            failures=$((failures+1))
            continue
        fi

        if [ "$i" -eq 0 ]; then
            echo "Checking image ${i} arches include amd64 and arm64..."
            if [[ " ${img_arches} " == *" amd64 "* && " ${img_arches} " == *" arm64 "* ]]; then
                echo "✅️ Image ${i} has required arches: ${img_arches}"
            else
                echo "🔴 Image ${i} missing required arches (need: amd64 and arm64), found: '${img_arches}'"
                failures=$((failures+1))
            fi
        else
            echo "Checking image ${i} arches include amd64..."
            if [[ " ${img_arches} " == *" amd64 "* ]]; then
                echo "✅️ Image ${i} has required arch: ${img_arches}"
            else
                echo "🔴 Image ${i} missing required arch (need: amd64), found: '${img_arches}'"
                failures=$((failures+1))
            fi
        fi

        echo "Checking image ${i} shasum is valid..."
        if [[ "${img_shasum}" == sha256:* ]]; then
            echo "✅️ Image ${i} shasum: ${img_shasum}"
        else
            echo "🔴 Image ${i} shasum missing or invalid: '${img_shasum}'"
            failures=$((failures+1))
        fi

        echo "Verifying image ${i} pullability with skopeo..."
        if [[ "${img_shasum}" == sha256:* ]]; then
            set +e
            if [ "$i" -eq 0 ]; then
                "${SCRIPT_DIR}/scripts/skopeo-verify-image.sh" \
                    "${img_url}" "${img_shasum}" \
                    "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml" \
                    "amd64 arm64"
            else
                "${SCRIPT_DIR}/scripts/skopeo-verify-image.sh" \
                    "${img_url}" "${img_shasum}" \
                    "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"
            fi
            local skopeo_rc=$?
            set -e
            if [ "${skopeo_rc}" -ne 0 ]; then
                echo "🔴 Image ${i} skopeo verification failed"
                failures=$((failures+1))
            else
                echo "✅️ Image ${i} is pullable"
            fi
        else
            echo "🔴 Skipping skopeo check for image ${i}: shasum not sha256:*"
            failures=$((failures+1))
        fi
    done

    echo ""
    echo "Checking mergerequest_url..."

    local mergerequest_url
    mergerequest_url=$(jq -r '.status.artifacts.merge_requests[0].url // ""' <<< "${release_json}")

    if [ -n "${mergerequest_url}" ]; then
        echo "✅️ mergerequest_url: ${mergerequest_url}"
    else
        echo "🔴 mergerequest_url was empty!"
        failures=$((failures+1))
    fi

    echo ""
    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    else
        echo "✅️ All multi-component release checks passed. Success!"
    fi
}
