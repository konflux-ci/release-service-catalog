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

      snapshot=$(jq -r '.spec.snapshot' <<< "${release_json}")
      echo "Snapshot: ${snapshot}"
      snapshot_json=$(kubectl get snapshot/"${snapshot}" -n "${RELEASE_NAMESPACE}" -ojson)
      revision=$(jq -r '.spec.components[0].source.git.revision' <<< "${snapshot_json}")
      echo "Revision: ${revision}"

      local failures=0
      local image_url image_shasum

      image_url=$(jq -r '.status.artifacts.images[0].urls[0] // ""' <<< "${release_json}")
      image_shasum=$(jq -r '.status.artifacts.images[0].shasum // ""' <<< "${release_json}")

      echo "Checking image_url..."
      if [ -n "${image_url}" ]; then
        echo "✅️ image_url: ${image_url}"
      else
        echo "🔴 image_url was empty!"
        failures=$((failures+1))
      fi

      echo "Checking image_shasum..."
      if [ -n "${image_shasum}" ]; then
        echo "✅️ image_shasum: ${image_shasum}"
      else
        echo "🔴 image_shasum was empty!"
        failures=$((failures+1))
      fi

      echo "Verifying image pullability with skopeo..."
      if [ -n "${image_url}" ] && [ -n "${image_shasum}" ]; then
        set +e
        "${SUITE_DIR}/../scripts/skopeo-verify-image.sh" \
          "${image_url}" "${image_shasum}" \
          "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"
        skopeo_return_code=$?
        set -e
        if [ "${skopeo_return_code}" -ne 0 ]; then
          failures=$((failures+1))
        fi
      else
        echo "⚠️  Skipping skopeo check: image_url or image_shasum is empty."
      fi

      set +e
      "${SUITE_DIR}/../scripts/find-pr-with-sha-and-file.sh" "hacbs-release/infra-deployments" "${revision}" "components/release/development/kustomization.yaml"
      find_return_code=$?
      set -e
      if [ "${find_return_code}" -eq 0 ]; then
        echo "✅️ find-pr-with-sha-and-file.sh found PRs"
      else
        echo "🔴 find-pr-with-sha-and-file.sh failed with return code ${find_return_code}"
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
