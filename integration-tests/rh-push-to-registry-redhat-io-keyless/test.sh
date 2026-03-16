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
    local image_url image_arch image_shasum
    local file_update_mr_url

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
    # --- Step 1: Strip the tag or digest from the original pullspec ---
    ORIGINAL_PULLSPEC="${image_url}"
    # Check if the pullspec contains a tag (:) or a digest (@)
    if [[ "$ORIGINAL_PULLSPEC" == *":"* && "$ORIGINAL_PULLSPEC" != *"@"* ]]; then
        # Contains a tag, strip it
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%:*}"
        echo "Stripped tag from: $ORIGINAL_PULLSPEC -> $STRIPPED_PULLSPEC"
    elif [[ "$ORIGINAL_PULLSPEC" == *"@"* ]]; then
        # Contains a digest, strip it
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%@*}"
        echo "Stripped digest from: $ORIGINAL_PULLSPEC -> $STRIPPED_PULLSPEC"
    else
        # No tag or digest found, use the original as is
        STRIPPED_PULLSPEC="$ORIGINAL_PULLSPEC"
        echo "No tag or digest found, using original as is: $STRIPPED_PULLSPEC"
    fi

    # --- Step 2: Concatenate the new digest to create the complete pullspec ---
    COMPLETE_PULLSPEC="${STRIPPED_PULLSPEC}@${image_shasum}"
    echo "New complete pullspec: $COMPLETE_PULLSPEC"

    DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG

    yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
        ${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml | base64 -d > ${DOCKER_CONFIG}/config.json

    # --- Step 3: Verify the new complete pullspec using skopeo ---
    if skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
        echo "✅️ Image '$COMPLETE_PULLSPEC' can be pulled using skopeo."
    else
        echo "🔴 Failed to pull or inspect image '$COMPLETE_PULLSPEC'."
        skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}"
        failures=$((failures+1))
    fi

    # --- Step 4: Verify keyless cosign signature ---
    echo "Verifying keyless cosign signature against Rekor at ${rekor_url}..."
    if cosign verify \
        --rekor-url="${rekor_url}" \
        --certificate-identity-regexp="system:serviceaccount:${managed_namespace}:.*" \
        --certificate-oidc-issuer="https://kubernetes.default.svc" \
        "${COMPLETE_PULLSPEC}"; then
        echo "✅️ Keyless cosign signature verified for '${COMPLETE_PULLSPEC}'."
    else
        echo "🔴 Keyless cosign signature verification failed for '${COMPLETE_PULLSPEC}'."
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
