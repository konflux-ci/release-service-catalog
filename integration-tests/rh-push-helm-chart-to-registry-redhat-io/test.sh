#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Override wait_for_component_initialization to also wait for the ImageRepository
# to become ready (quay repo created, push secret linked to build SA).
eval "$(declare -f wait_for_component_initialization \
  | sed '1s/wait_for_component_initialization/_base_wait_for_component_initialization/')"

wait_for_component_initialization() {
    _base_wait_for_component_initialization

    echo "Waiting for ImageRepository ${image_repository_name} to be ready..."
    local ir_attempts=0
    local ir_max=30
    while [ $ir_attempts -lt $ir_max ]; do
        local ir_state
        ir_state=$(kubectl get imagerepository/"${image_repository_name}" \
            -n "${tenant_namespace}" -o jsonpath='{.status.state}' 2>/dev/null || true)
        if [ "${ir_state}" = "ready" ]; then
            echo "✅ ImageRepository is ready"
            return 0
        fi
        ir_attempts=$((ir_attempts + 1))
        echo "  ImageRepository state: ${ir_state:-pending} (attempt ${ir_attempts}/${ir_max})"
        sleep 5
    done
    echo "🔴 ImageRepository ${image_repository_name} did not become ready after $((ir_max * 5))s"
    kubectl get imagerepository/"${image_repository_name}" -n "${tenant_namespace}" -o yaml 2>&1 || true
    exit 1
}

# Function to verify Release contents
# Relies on global variables: RELEASE_NAMES, RELEASE_NAMESPACE, SUITE_DIR, component_name
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
    local image_url image_arch image_shasum
    local catalog_url file_update_mr_url

    image_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image_arch=$(jq -r '.status.artifacts.images[0]?.arches[0] // ""' <<< "${release_json}")
    image_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")
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

    echo "Checking Image URL..."
    if [ -n "${image_url}" ]; then
        echo "✅️ image_url: ${image_url}"
    else
        echo "🔴 image_url was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Arch..."
    if [ -n "${image_arch}" ]; then
        echo "✅️ image_arch: ${image_arch}"
    else
        echo "🔴 image_arch was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Shasum..."
    if [ -n "${image_shasum}" ]; then
        echo "✅️ image_shasum: ${image_shasum}"
    else
        echo "🔴 image_shasum was empty"
        failures=$((failures+1))
    fi

    echo "Verifying image pullability with skopeo..."
    ORIGINAL_PULLSPEC="${image_url}"
    if [[ "$ORIGINAL_PULLSPEC" == *":"* && "$ORIGINAL_PULLSPEC" != *"@"* ]]; then
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%:*}"
    elif [[ "$ORIGINAL_PULLSPEC" == *"@"* ]]; then
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%@*}"
    else
        STRIPPED_PULLSPEC="$ORIGINAL_PULLSPEC"
    fi

    COMPLETE_PULLSPEC="${STRIPPED_PULLSPEC}@${image_shasum}"
    echo "Pullspec: $COMPLETE_PULLSPEC"

    DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG

    yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml" | base64 -d > "${DOCKER_CONFIG}/config.json"

    # Helm OCI artifacts require --raw (mediaType is application/vnd.cncf.helm.config.v1+json)
    if skopeo inspect --tls-verify=true --raw --retry-times 3 "docker://${COMPLETE_PULLSPEC}" 2>/dev/null | \
        jq -e '.config.mediaType == "application/vnd.cncf.helm.config.v1+json"' &>/dev/null; then
        echo "✅️ Helm OCI artifact '$COMPLETE_PULLSPEC' verified with skopeo inspect --raw."
    elif skopeo inspect --tls-verify=true --retry-times 3 "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
        echo "✅️ Image '$COMPLETE_PULLSPEC' can be inspected with skopeo inspect."
    else
        echo "🔴 Failed to inspect '$COMPLETE_PULLSPEC' as Helm OCI artifact or container image."
        skopeo inspect --tls-verify=true --raw --retry-times 3 "docker://${COMPLETE_PULLSPEC}" | head -c 500 || true
        failures=$((failures+1))
    fi

    rm -rf "${DOCKER_CONFIG}"

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
