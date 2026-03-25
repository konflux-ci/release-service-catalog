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
    set +e
    "${SUITE_DIR}/../scripts/skopeo-verify-image.sh" \
        "${image_url}" "${image_shasum}" \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"
    skopeo_return_code=$?
    set -e
    if [ "${skopeo_return_code}" -ne 0 ]; then
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
