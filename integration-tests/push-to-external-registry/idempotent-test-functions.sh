#!/usr/bin/env bash
#
# idempotent-test-functions.sh - Helper functions for push-to-external-registry idempotent test
#
# This file contains custom functions used by the idempotent release test.
# It is sourced by run-idempotent-test.sh (NOT by standard run-test.sh).
#
# Functions:
#   - verify_release_contents()         : Validates Release artifacts and image pullability
#   - wait_for_release()                : Wrapper for wait-for-release.sh script
#   - get_pipelinerun_name_from_release(): Extracts PipelineRun name from Release CR
#   - get_release_json()                : Gets Release CR as JSON
#   - were_all_components_filtered()    : Checks if all components were filtered (idempotency check)
#   - is_taskrun_skipped()              : Checks if a pipeline task was skipped
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Function to verify Release contents
# Validates that the release has correct artifacts and the image can be pulled
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SUITE_DIR
verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(get_release_json "${RELEASE_NAME}")
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    local failures=0
    local image_url image_arch image_shasum

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

    if [ "${failures}" -gt 0 ]; then
      echo "🔴 Test has FAILED with ${failures} failure(s)!"
      exit 1
    else
      echo "✅️ All release checks passed. Success!"
    fi
}

# Wrapper for wait-for-release.sh script
# Sets required environment variables and calls the shared wait script
wait_for_release() {
    local release_name=$1
    local namespace=$2
    
    export RELEASE_NAME="${release_name}"
    export RELEASE_NAMESPACE="${namespace}"
    
    "${SCRIPT_DIR}/../scripts/wait-for-release.sh"
}

# Helper: Get PipelineRun name from Release CR
# Returns just the PipelineRun name (without namespace prefix)
get_pipelinerun_name_from_release() {
    local release_name=$1
    
    # Get the actual PipelineRun name from the Release CR
    # Format is: namespace/name, we need just the name part
    local pipelinerun_full
    pipelinerun_full=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null)
    
    if [ -z "${pipelinerun_full}" ]; then
        return 1
    fi
    
    # Extract and return just the name part after the /
    basename "${pipelinerun_full}"
}

# Helper: Get release as JSON
get_release_json() {
    local release_name=$1
    kubectl get release "${release_name}" -n "${tenant_namespace}" -o json
}

# Check if all components were filtered (idempotency validation)
# Returns 0 (true) if push-snapshot task was skipped, 1 (false) otherwise
# Used to validate that the second release correctly filtered already-released components
were_all_components_filtered() {
    local release_name=$1

    # Check if all components were filtered by seeing if push-snapshot was skipped
    # We trust the pipeline's when condition to skip push-snapshot when skip_release=true
    is_taskrun_skipped "${release_name}" "push-snapshot"
}

# Check if a specific task was skipped in the pipeline
# Returns 0 (true) if task was skipped, 1 (false) otherwise
is_taskrun_skipped() {
    local release_name=$1
    local task_name=$2

    local pipelinerun_name
    pipelinerun_name=$(get_pipelinerun_name_from_release "${release_name}") || return 1

    # Check if task appears in PipelineRun's skippedTasks list
    # Skipped tasks don't create TaskRuns, they're only in the PipelineRun status
    local skipped_task
    skipped_task=$(kubectl get pipelinerun "${pipelinerun_name}" -n "${managed_namespace}" \
        -o jsonpath="{.status.skippedTasks[?(@.name=='${task_name}')].name}" 2>/dev/null)

    [[ -n "${skipped_task}" ]]
}
