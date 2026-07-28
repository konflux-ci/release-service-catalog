# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # Default to true

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
      local url
      local advisory_url

      url=$(jq -r '.status.artifacts."github-release".url // ""' <<< "${release_json}")
      advisory_url="$(jq -r '.status.artifacts.advisory.url // ""' <<< "${release_json}" 2>/dev/null || true)"
      echo "Checking url: ${url}..."
      if [ -n "${url}" ]; then
        # get tag from URL
        # https://github.com/scoheb/e2e-base/releases/tag/v86.15272
        tag=$(awk -F'/' '{print $NF}' <<< "${url}")
        echo "Tag: ${tag}"
        if [ "${tag}" == "v86.${uuid}" ]; then
          echo "✅️ tag found ($tag) is what was expected"
          "${SUITE_DIR}/../scripts/verify-github-release.sh" "${component_repo_name}" "${tag}"
          echo "✅️ url is valid and exists: ${url}"
        else
          echo "🔴 tag found ($tag) is not what was expected. Expected: v86.${uuid}"
          failures=$((failures+1))
        fi
      else
        echo "🔴 url was empty!"
        failures=$((failures+1))
      fi

      echo "Checking advisory URL..."
      if [ -n "${advisory_url}" ]; then
        echo "✅️ advisory_url: ${advisory_url}"
      else
        echo "🔴 advisory_url was empty!"
        failures=$((failures+1))
      fi

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

patch_component_source() {
  echo "Patching component source..."
  set +x
  # Get secret value from the tenant secrets file and use
  # it for GH_TOKEN
  secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' ${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml)
  export GH_TOKEN=${secret_value}
  # We rename the file so that the github release task
  # will create a new release that we can assert that it exists
  # after the test is done
  "${SCRIPT_DIR}/scripts/rename-github-file.sh" "${component_repo_name}" "main_86.15272_SHA256SUMS" "main_86.${uuid}_SHA256SUMS" -b "${component_branch}"
  echo "✅️ Successfully patched component source!"
}
