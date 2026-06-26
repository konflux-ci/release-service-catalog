# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # Default to true
# GitHub API curl retries (override in CI/local: export GITHUB_API_CURL_RETRY=5)
GITHUB_API_CURL_RETRY="${GITHUB_API_CURL_RETRY:-3}"

# Variables that will be set by functions and used globally:
# component_branch, component_base_branch, component_repo_name (from test.env or similar)
# managed_namespace, tenant_namespace, application_name, component_name (from test.env or similar)
# managed_sa_name (from test.env or similar)
# GITHUB_TOKEN, VAULT_PASSWORD_FILE (from test.env)
# SCRIPT_DIR (where run-test.sh is located)
# LIB_DIR (where lib/ is located)
# tmpDir (set by create_kubernetes_resources)
# component_pr, pr_number (set by wait_for_component_initialization)
# SHA (set by merge_github_pr)
# component_push_plr_name (set by wait_for_plr_to_appear)
# RELEASE_NAME, RELEASE_NAMESPACE (set and exported by wait_for_release)

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

# Function to verify Release contents
# Relies on global variables: RELEASE_NAMES, RELEASE_NAMESPACE, SCRIPT_DIR, managed_namespace, managed_sa_name, NO_CVE
verify_release_contents() {

    local failed_releases
    for RELEASE_NAME in ${RELEASE_NAMES};
    do
      echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
      local release_json
      release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
      if [ -z "$release_json" ]; then
          log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
      fi

      local failures=0
      local mergerequest_url released_status

      mergerequest_url=$(jq -r '.status.artifacts.merge_requests[0]?.url? // ""' <<< "${release_json}")
      released_status=$(jq -r '([.status.conditions[]? | select(.type=="Released") | .status] | first) // ""' <<< "${release_json}")

      echo "Release fields under validation:"
      echo "  Released: ${released_status}"
      echo "  mergerequest_url: ${mergerequest_url}"

      echo "Checking Released=True..."
      if [ "${released_status}" = "True" ]; then
        echo "✅️ Released=True"
      else
        echo "🔴 Released was not True (found: '${released_status}')"
        failures=$((failures+1))
      fi

      echo "Checking mergerequest_url..."
      if [ -n "${mergerequest_url}" ]; then
        echo "✅️ mergerequest_url: ${mergerequest_url}"
      else
        echo "🔴 mergerequest_url was empty!"
        failures=$((failures+1))
      fi

      # Verify container images using shared helper
      local failed_releases=""
      check_container_images

      if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        failed_releases="${RELEASE_NAME} ${failed_releases}"
      else
        echo "✅️ All release checks passed. Success!"
      fi
    done

    if [ -n "${failed_releases}" ]; then
      echo "🔴 Releases FAILED: ${failed_releases}"
      exit 1
    else
      echo "✅️ Success!"
    fi
}
