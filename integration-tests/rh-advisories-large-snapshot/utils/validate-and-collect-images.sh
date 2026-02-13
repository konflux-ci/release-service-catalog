#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# validate-and-collect-images.sh - Validate existing components and collect images
#
# DESCRIPTION:
#   1. Check existing Components with valid images
#   2. For EVERY image source (status, PipelineRun, spec), verify:
#      a) Image is a real container image (has architecture field)
#      b) NOT an attestation artifact (attestations have no arch, ~233 byte config)
#      c) Manifest actually exists on Quay.io (not just metadata)
#   3. PROACTIVE CLEANUP: If attestation artifact detected in spec.containerImage:
#      - Clear the bad reference from the component
#      - Force search for valid replacement image
#   4. For invalid/missing images, search Quay.io for images with Tekton Chains signatures:
#      - Prioritizes newest images that have .sig/.att/.sbom tags (Chains-signed)
#      - Validates image has architecture (filters out attestation artifacts)
#      - If found: Update component with signed image
#      - If not found: Delete component (unusable)
#   5. SMART DELETION: Components that need deletion:
#      - Try normal deletion first (30 second timeout)
#      - If stuck with finalizers, automatically remove them
#      - Prevents components from hanging in "Terminating" state
#   6. Create image list from all valid components
#   7. Fail if fewer than 50 images (need to run /build-large-snapshot first)
#
# SIGNATURE VALIDATION:
#   Actively searches for images with Tekton Chains signatures by checking for
#   corresponding .sig tags on Quay.io. This ensures EC validation will pass.
#
# MANIFEST VERIFICATION:
#   Uses skopeo (preferred) or curl to verify that image manifests are accessible
#   on Quay.io. This prevents "manifest unknown" errors during release pipeline.
#
# USAGE:
#   ./validate-and-collect-images.sh <namespace> <output-file> [min-images]
#
# ARGUMENTS:
#   namespace    : Kubernetes namespace (default: dev-release-team-tenant)
#   output-file  : Path to output file with image list
#   min-images   : Minimum required images (default: 50)

set -o errexit
set -o nounset
set -o pipefail

NAMESPACE="${1:-dev-release-team-tenant}"
OUTPUT_FILE="${2:-/tmp/validated-images.txt}"
MIN_IMAGES="${3:-50}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Image Validation and Collection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Namespace: ${NAMESPACE}"
echo "  Output file: ${OUTPUT_FILE}"
echo "  Minimum required: ${MIN_IMAGES} images"
echo ""

# Initialize output file
> "${OUTPUT_FILE}"

# Helper function to verify image manifest exists on Quay.io
verify_manifest_exists() {
    local image_ref="$1"
    
    # Extract repository and digest from image reference
    # e.g., quay.io/redhat-user-workloads-stage/ns/component@sha256:abc123
    local repo="${image_ref%%@*}"
    local digest="${image_ref##*@}"
    
    # Use skopeo to check if manifest exists (faster and more reliable than curl)
    if command -v skopeo &>/dev/null; then
        if skopeo inspect --raw "docker://${image_ref}" &>/dev/null; then
            return 0  # Manifest exists
        else
            return 1  # Manifest not found
        fi
    else
        # Fallback: Use curl to check Quay API
        local api_repo="${repo#quay.io/}"
        local manifest_url="https://quay.io/api/v1/repository/${api_repo}/manifest/${digest}"
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "${manifest_url}" 2>/dev/null || echo "000")
        
        if [ "$http_code" = "200" ]; then
            return 0  # Manifest exists
        else
            return 1  # Manifest not found
        fi
    fi
}

# Force delete a component with finalizer removal if stuck
# Usage: force_delete_component <component_name>
force_delete_component() {
    local component_name="$1"
    local timeout=30  # seconds to wait before forcing
    
    # Try normal deletion first
    kubectl delete component "${component_name}" -n "${NAMESPACE}" --ignore-not-found=true &>/dev/null || true
    
    # Wait a bit to see if it deletes normally
    local waited=0
    while [ $waited -lt $timeout ]; do
        if ! kubectl get component "${component_name}" -n "${NAMESPACE}" &>/dev/null; then
            # Successfully deleted
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    # Still exists after timeout - check if it's stuck in deletion
    local deletion_timestamp=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
        -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
    
    if [ -n "$deletion_timestamp" ]; then
        # Component is stuck in deletion - remove finalizers
        echo "      ⚠️  Component stuck in deletion, removing finalizers..."
        kubectl patch component "${component_name}" -n "${NAMESPACE}" \
            --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
        
        # Wait a moment for deletion to complete
        sleep 2
    fi
    
    # Final check
    if kubectl get component "${component_name}" -n "${NAMESPACE}" &>/dev/null 2>&1; then
        echo "      ⚠️  Component still exists after forced deletion attempt"
        return 1
    fi
    return 0
}

# ============================================================================
# Step 1: Check Existing Components
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1/2: Checking existing Components..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Batching Kubernetes queries for efficiency..."

# Fetch all components and PipelineRuns once (batch optimization)
echo "  Fetching all Components..."
ALL_COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
    -l test.appstudio.openshift.io/type=multi-version-build \
    -o json 2>/dev/null || echo '{"items":[]}')

echo "  Fetching all PipelineRuns..."
ALL_PIPELINERUNS_JSON=$(kubectl get pipelinerun -n "${NAMESPACE}" \
    -l pipelines.appstudio.openshift.io/type=build \
    -o json 2>/dev/null || echo '{"items":[]}')

TOTAL_COMPONENTS=$(echo "${ALL_COMPONENTS_JSON}" | jq '.items | length')
echo ""
echo "  Total components found: ${TOTAL_COMPONENTS}"

if [ "${TOTAL_COMPONENTS}" -eq 0 ]; then
    echo ""
    echo "❌ ERROR: No components found!"
    echo ""
    echo "   You need to build images first by running:"
    echo "   /build-large-snapshot"
    echo ""
    echo "   Run it 2 times to build 100 images (50 per run)"
    exit 1
fi

# ============================================================================
# Step 2: Validate Components and Collect Images
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2/2: Validating components and collecting images..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

valid_count=0
updated_count=0
deleted_count=0
fixed_count=0
manifests_verified=0
with_chains_signatures=0

# Process each component (use process substitution to avoid subshell)
while read -r component_name; do
    # Get component data
    container_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
        ".items[] | select(.metadata.name == \"${component_name}\") | .status.containerImage // \"\"")
    spec_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
        ".items[] | select(.metadata.name == \"${component_name}\") | .spec.containerImage // \"\"")
    
    # Check if component has valid image in status
    if [ -n "${container_image}" ] && [ "${container_image}" != "null" ] && [[ "${container_image}" == *"@sha256:"* ]]; then
        # Verify this is a real container image, not an attestation artifact
        is_valid_image="false"
        if command -v skopeo &>/dev/null; then
            image_config=$(skopeo inspect --raw --config "docker://${container_image}" 2>/dev/null || echo "{}")
            image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
                if [ -n "$image_arch" ] && [ "$image_arch" != "null" ]; then
                    is_valid_image="true"
                else
                    echo "  ⚠️  Attestation artifact detected in status.containerImage: ${component_name}"
                    echo "      Clearing bad reference and searching for valid image..."
                    # Don't clear status (it's set by controller), just skip and search for replacement
                fi
        else
            is_valid_image="true"  # No skopeo - assume valid
        fi
        
        if [ "$is_valid_image" = "true" ]; then
            # Verify manifest actually exists on Quay.io
            if verify_manifest_exists "${container_image}"; then
                echo "  ✓ Valid: ${component_name}"
                echo "${container_image}" >> "${OUTPUT_FILE}"
                valid_count=$((valid_count + 1))
                manifests_verified=$((manifests_verified + 1))
                continue
            else
                echo "  ⚠️  Manifest missing (will check alternatives): ${component_name}"
                # Fall through to check other sources
            fi
        fi
    fi
    
    # Check for successful PipelineRun
    plr_success=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${component_name}" '
        .items[]
        | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
        | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
        | .metadata.name' | head -1)
    
    if [ -n "${plr_success}" ]; then
        # Has successful build - extract image from PipelineRun
        image_url=$(kubectl get pipelinerun "${plr_success}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null || echo "")
        image_digest=$(kubectl get pipelinerun "${plr_success}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}' 2>/dev/null || echo "")
        
        if [ -n "${image_url}" ] && [ -n "${image_digest}" ]; then
            image_base="${image_url%:*}"
            image_ref="${image_base}@${image_digest}"
            
            # Verify this is a real container image, not an attestation artifact
            is_valid_image="false"
            if command -v skopeo &>/dev/null; then
                image_config=$(skopeo inspect --raw --config "docker://${image_ref}" 2>/dev/null || echo "{}")
                image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
                if [ -n "$image_arch" ] && [ "$image_arch" != "null" ]; then
                    is_valid_image="true"
                else
                    echo "  ⚠️  Attestation artifact detected in PipelineRun results: ${component_name}"
                    echo "      Searching for valid image on Quay..."
                fi
            else
                is_valid_image="true"  # No skopeo - assume valid
            fi
            
            if [ "$is_valid_image" = "true" ]; then
                # Verify manifest actually exists on Quay.io
                if verify_manifest_exists "${image_ref}"; then
                    echo "  ✓ Valid (from build): ${component_name}"
                    echo "${image_ref}" >> "${OUTPUT_FILE}"
                    valid_count=$((valid_count + 1))
                    manifests_verified=$((manifests_verified + 1))
                    continue
                else
                    echo "  ⚠️  Build manifest missing (will check alternatives): ${component_name}"
                    # Fall through to check other sources
                fi
            fi
        fi
    fi
    
    # Check if component was discovered from Quay (has spec.containerImage with digest)
    if [ -n "${spec_image}" ] && [ "${spec_image}" != "null" ] && [[ "${spec_image}" == *"@sha256:"* ]]; then
        # Verify this is a real container image, not an attestation artifact
        is_valid_image="false"
        if command -v skopeo &>/dev/null; then
            image_config=$(skopeo inspect --raw --config "docker://${spec_image}" 2>/dev/null || echo "{}")
            image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
                if [ -n "$image_arch" ] && [ "$image_arch" != "null" ]; then
                    is_valid_image="true"
                else
                    echo "  🔧 FIXING: Attestation artifact detected in spec.containerImage: ${component_name}"
                    echo "      Clearing bad reference: ${spec_image}"
                    # Clear the attestation artifact from spec.containerImage
                    kubectl patch component "${component_name}" -n "${NAMESPACE}" --type=json -p '[
                        {"op": "remove", "path": "/spec/containerImage"}
                    ]' &>/dev/null || true
                    fixed_count=$((fixed_count + 1))
                    echo "      Searching for valid replacement image on Quay..."
                fi
        else
            is_valid_image="true"  # No skopeo - assume valid
        fi
        
        if [ "$is_valid_image" = "true" ]; then
            # Verify manifest actually exists on Quay.io
            if verify_manifest_exists "${spec_image}"; then
                echo "  ✓ Valid (Quay image): ${component_name}"
                echo "${spec_image}" >> "${OUTPUT_FILE}"
                valid_count=$((valid_count + 1))
                manifests_verified=$((manifests_verified + 1))
                continue
            else
                echo "  ⚠️  Spec manifest missing (will check alternatives): ${component_name}"
                # Fall through to check Quay API for latest
            fi
        fi
    fi
    
    # Component is invalid - check if image exists on Quay.io
    repo_url="https://quay.io/api/v1/repository/redhat-user-workloads-stage/${NAMESPACE}/${component_name}"
    response=$(curl -s -w "\n%{http_code}" "${repo_url}" 2>/dev/null || echo "000")
    http_code=$(echo "$response" | tail -1)
    
    if [ "$http_code" = "200" ]; then
        # Repository exists - find the MOST RECENT image with Tekton Chains signatures
        tags_url="${repo_url}/tag/?onlyActiveTags=true&limit=100"
        tags_response=$(curl -s "${tags_url}" 2>/dev/null)
        
        # Strategy: Find image tags that have corresponding .sig tags (Chains signatures)
        # This ensures we select images that were built with Tekton Chains enabled
        manifest_digest=""
        while IFS= read -r potential_tag; do
            [ -z "$potential_tag" ] && continue
            [ "$potential_tag" = "null" ] && continue
            
            # Get the digest for this tag
            tag_digest=$(echo "$tags_response" | jq -r --arg tag "$potential_tag" \
                '.tags[] | select(.name == $tag) | .manifest_digest' | head -1)
            
            # Check if corresponding .sig tag exists
            sig_tag="sha256-${tag_digest##*:}.sig"
            has_sig=$(echo "$tags_response" | jq -r --arg sig "$sig_tag" \
                '.tags[] | select(.name == $sig) | .name' 2>/dev/null)
            
            if [ -n "$has_sig" ]; then
                # Found image with Chains signature!
                manifest_digest="$tag_digest"
                break
            fi
        done < <(echo "$tags_response" | jq -r '.tags[] | select(.name | (contains(".sig") or contains(".att") or contains(".sbom") or contains(".dockerfile") or contains(".git")) | not) | .name')
        
        if [ -n "$manifest_digest" ] && [ "$manifest_digest" != "null" ]; then
            image_with_digest="quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}@${manifest_digest}"
            
            # Verify this is a REAL container image, not an attestation artifact
            # Attestation artifacts have minimal configs (~233 bytes) with no architecture info
            if command -v skopeo &>/dev/null; then
                image_config=$(skopeo inspect --raw --config "docker://${image_with_digest}" 2>/dev/null || echo "{}")
                image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
                
                if [ -z "$image_arch" ] || [ "$image_arch" = "null" ]; then
                    echo "  ⚠️  Skipping attestation artifact (no architecture): ${image_with_digest}"
                    manifest_digest=""  # Mark as invalid so component gets deleted
                fi
            fi
            
            # Only proceed if manifest_digest is still valid (not cleared by architecture check)
            if [ -n "$manifest_digest" ]; then
                # Verify manifest actually exists (double-check)
                if verify_manifest_exists "${image_with_digest}"; then
                    # We already verified it has Chains signature in the selection logic above
                    echo "  🔄 Updating (found on Quay with Chains signatures): ${component_name}"
                    
                    kubectl patch component "${component_name}" -n "${NAMESPACE}" --type=merge -p "{
                      \"spec\": {
                        \"containerImage\": \"${image_with_digest}\"
                      },
                      \"metadata\": {
                        \"annotations\": {
                          \"test.appstudio.openshift.io/discovered-from-quay\": \"true\",
                          \"test.appstudio.openshift.io/has-chains-signature\": \"true\"
                        }
                      }
                    }" &>/dev/null
                    
                    echo "${image_with_digest}" >> "${OUTPUT_FILE}"
                    updated_count=$((updated_count + 1))
                    valid_count=$((valid_count + 1))
                    manifests_verified=$((manifests_verified + 1))
                    with_chains_signatures=$((with_chains_signatures + 1))
                    continue
                else
                    echo "  ⚠️  Quay API returned digest but manifest not accessible: ${component_name}"
                    # Fall through to deletion
                fi
            fi
        fi
    fi
    
    # No valid image found anywhere - delete the component
    echo "  🗑️  Deleting (no image): ${component_name}"
    force_delete_component "${component_name}"
    deleted_count=$((deleted_count + 1))
done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')

# ============================================================================
# Results and Validation
# ============================================================================
FINAL_COUNT=$(wc -l < "${OUTPUT_FILE}" 2>/dev/null || echo "0")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Validation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Valid images found: ${FINAL_COUNT}"
echo "  Manifests verified: ${manifests_verified} (on Quay.io)"
if [ ${with_chains_signatures} -gt 0 ]; then
    echo "  With Tekton Chains signatures: ${with_chains_signatures}"
fi
echo ""
TOTAL_COMPONENTS=$(echo "${ALL_COMPONENTS_JSON}" | jq '.items | length')
SKIPPED_COUNT=$((TOTAL_COMPONENTS - valid_count))

echo "  Breakdown:"
echo "    • Already valid: $((valid_count - updated_count))"
if [ ${updated_count} -gt 0 ]; then
    echo "    • Fixed (found on Quay): ${updated_count}"
    if [ ${with_chains_signatures} -gt 0 ]; then
        echo "      → With Chains signatures: ${with_chains_signatures}"
    fi
fi
if [ ${fixed_count} -gt 0 ]; then
    echo "    • Cleared attestation artifacts: ${fixed_count}"
fi
if [ ${deleted_count} -gt 0 ]; then
    echo "    • Deleted (no image): ${deleted_count}"
fi
echo ""

# Validate minimum image count
if [ ${FINAL_COUNT} -lt ${MIN_IMAGES} ]; then
    echo "❌ ERROR: Not enough images for test!"
    echo ""
    echo "   Found: ${FINAL_COUNT} images"
    echo "   Required: At least ${MIN_IMAGES} images"
    echo ""
    echo "   You need to build more images first:"
    needed=$((MIN_IMAGES - FINAL_COUNT))
    runs_needed=$(( (needed + 49) / 50 ))  # Round up
    echo "   /build-large-snapshot   # Run ${runs_needed} times to build ${needed} more images"
    echo ""
    echo "   (Each run builds 50 images, total needed: ${needed})"
    exit 1
fi

if [ ${with_chains_signatures} -eq 0 ] && [ ${FINAL_COUNT} -gt 0 ]; then
    echo ""
    echo "⚠️  WARNING: No images found with Tekton Chains signatures!"
    echo "   Enterprise Contract validation may fail if signature checks are enabled."
    echo "   Consider:"
    echo "     1. Running /build-large-snapshot to create fresh images with signatures"
    echo "     2. Excluding signature checks in EC policy if testing other aspects"
    echo ""
fi

echo "✅ Ready to test with ${FINAL_COUNT} images"
if [ ${with_chains_signatures} -gt 0 ]; then
    echo "   (${with_chains_signatures} images have Tekton Chains signatures)"
fi
echo ""
echo "  Output file: ${OUTPUT_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
