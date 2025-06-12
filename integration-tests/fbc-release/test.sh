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
      local fbc_fragment ocp_version iib_log index_image index_image_resolved

      fbc_fragment=$(jq -r '.status.artifacts.components[0].fbc_fragment // ""' <<< "${release_json}")
      ocp_version=$(jq -r '.status.artifacts.components[0].ocp_version // ""' <<< "${release_json}")
      iib_log=$(jq -r '.status.artifacts.components[0].iibLog // ""' <<< "${release_json}")

      index_image=$(jq -r '.status.artifacts.index_image.index_image // ""' <<< "${release_json}")
      index_image_resolved=$(jq -r '.status.artifacts.index_image.index_image_resolved // ""' <<< "${release_json}")

      echo "Checking fbc_fragment..."
      if [ -n "${fbc_fragment}" ]; then
        echo "✅️ fbc_fragment: ${fbc_fragment}"
      else
        echo "🔴 fbc_fragment was empty!"
        failures=$((failures+1))
      fi
      echo "Checking ocp_version..."
      if [ -n "${ocp_version}" ]; then
        echo "✅️ ocp_version: ${ocp_version}"
      else
        echo "🔴 ocp_version was empty!"
        failures=$((failures+1))
      fi
      echo "Checking iib_log..."
      if [ -n "${iib_log}" ]; then
        echo "✅️ iib_log: ${iib_log}"
      else
        echo "🔴 iib_log was empty!"
        failures=$((failures+1))
      fi
      echo "Checking index_image..."
      if [ -n "${index_image}" ]; then
        echo "✅️ index_image: ${index_image}"
      else
        echo "🔴 index_image was empty!"
        failures=$((failures+1))
      fi
      echo "Checking index_image_resolved..."
      if [ -n "${index_image_resolved}" ]; then
        echo "✅️ index_image_resolved: ${index_image_resolved}"
      else
        echo "🔴 index_image_resolved was empty!"
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
