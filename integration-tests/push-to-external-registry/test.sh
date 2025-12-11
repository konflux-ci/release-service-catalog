#!/usr/bin/env bash
#
# test.sh - Test-specific functions for push-to-external-registry (standard test)
#
# This file contains functions for the standard single-release test flow.
# It is sourced by run-test.sh.
#
# For idempotent (two-release) testing, see idempotent-test-functions.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="false"  # Include CVE in commits by default

# Function to verify Release contents
# Relies on global variables: RELEASE_NAMES, RELEASE_NAMESPACE, SUITE_DIR
verify_release_contents() {
    local failed_releases=""
    
    for RELEASE_NAME in ${RELEASE_NAMES}; do
        echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
        local release_json
        release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
        if [ -z "$release_json" ]; then
            log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
        fi

        echo "Release JSON: ${release_json}"

        local failures=0
        local image_url

        image_url=$(jq -r '.status.artifacts.images[0].urls[0] // ""' <<< "${release_json}")

        echo "Checking image_url..."
        if [ -n "${image_url}" ]; then
            echo "✅️ image_url: ${image_url}"
        else
            echo "🔴 image_url was empty!"
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

