#!/usr/bin/env bash
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Function to verify Release contents
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SUITE_DIR, managed_namespace
verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    local failures=0
    local image_url image_arch

    image_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image_arch=$(jq -r '.status.artifacts.images[0]?.arches[0] // ""' <<< "${release_json}")
    image_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")

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

    # Verify componentTags combination with defaults.tags and repository tags
    echo "Verifying tag combination from all sources..."
    image_urls=$(jq -r '.status.artifacts.images[0].urls[]? // ""' <<< "${release_json}")
    url_count=$(jq -r '.status.artifacts.images[0].urls | length // 0' <<< "${release_json}")

    echo "All image URLs with tags:"
    echo "${image_urls}"
    echo "Total tags applied: ${url_count}"

    # Expected tags after deduplication:
    # - defaults.tags: latest, {{ timestamp }}
    # - componentTags: latest (duplicate, removed), {{ release_timestamp }}
    # - repository tags: {{ git_sha }}, {{ git_short_sha }}, {{ digest_sha }}, v1.0.0, {{ oci_version }}
    # Expected minimum: 8 unique tags (latest appears only once due to deduplication)
    expected_min_tags=8

    if [ "${url_count}" -ge "${expected_min_tags}" ]; then
        echo "✅️ Found ${url_count} image URLs (expected at least ${expected_min_tags})"
    else
        echo "🔴 Found only ${url_count} image URLs, expected at least ${expected_min_tags}"
        failures=$((failures+1))
    fi

    # Verify tags from defaults.tags
    if echo "${image_urls}" | grep -q ":latest"; then
        echo "✅️ Found 'latest' tag (from defaults.tags and componentTags, deduplicated)"
    else
        echo "🔴 Missing 'latest' tag from defaults.tags/componentTags"
        failures=$((failures+1))
    fi

    # Verify tags from repository-specific tags
    if echo "${image_urls}" | grep -q ":v1.0.0"; then
        echo "✅️ Found 'v1.0.0' tag from repository tags"
    else
        echo "🔴 Missing 'v1.0.0' tag from repository tags"
        failures=$((failures+1))
    fi

    if [ "${failures}" -gt 0 ]; then
      echo "🔴 Test has FAILED with ${failures} failure(s)!"
      exit 1
    else
      echo "✅️ All release checks passed. Success!"
    fi
}
