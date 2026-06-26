#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Function to verify Release contents
# Modifies global variable: advisory_yaml_dir
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SCRIPT_DIR, managed_namespace, managed_sa_name, NO_CVE
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

    local catalog_url
    local failures=0
    local failed_releases=""
    local file_update_mr_url

    catalog_url=$(jq -r '.status.artifacts.catalog_urls[]?.url // ""' <<< "${release_json}")
    file_update_mr_url=$(jq -r '.status.artifacts.merge_requests[0]?.url // ""' <<< "${release_json}")

    echo "Checking Catalog URL..."
    if [ -n "${catalog_url}" ]; then
        echo "✅️ catalog_url: ${catalog_url}"
    else
        echo "🔴 catalog_url was empty"
        failures=$((failures+1))
    fi

    echo "Checking File Update MR URL..."
    if [ -n "${file_update_mr_url}" ]; then
        echo "✅️ file_update_mr_url: ${file_update_mr_url}"
    else
        echo "🔴 file_update_mr_url was empty"
        failures=$((failures+1))
    fi

    # Verify container images using shared helper (single-arch)
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
