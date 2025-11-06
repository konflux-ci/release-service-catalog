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

