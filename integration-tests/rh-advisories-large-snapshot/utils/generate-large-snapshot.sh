#!/usr/bin/env bash
#
# generate-large-snapshot.sh - Utility to generate a large snapshot manifest
#
# This script creates a Snapshot CR with approximately 200 components
# for testing the rh-advisories pipeline with worst-case signing performance.
#
# REQUIRES: Fresh Konflux builds (unsigned images)
#   Run: ./test.sh (builds + tests)
#
# Usage:
#   FRESH_BUILDS_FILE=/tmp/fresh-images-pool.txt \
#     ./generate-large-snapshot.sh <snapshot-name> <application-name> <namespace> [component-count]
#
# Arguments:
#   snapshot-name      : Name for the snapshot
#   application-name   : Name of the application
#   namespace          : Kubernetes namespace
#   component-count    : Number of components (default: 200)
#
# Environment:
#   FRESH_BUILDS_FILE  : Path to fresh builds file (REQUIRED)
#
# Output:
#   Writes snapshot YAML to stdout
#
# Example:
#   export FRESH_BUILDS_FILE=/tmp/fresh-images-pool.txt
#   ./generate-large-snapshot.sh my-snapshot my-app dev-tenant 200 > snapshot.yaml
#   kubectl apply -f snapshot.yaml
#

set -euo pipefail

SNAPSHOT_NAME="${1:-large-snapshot}"
APPLICATION_NAME="${2:-test-app}"
NAMESPACE="${3:-dev-release-team-tenant}"
COMPONENT_COUNT="${4:-200}"

# Validate COMPONENT_COUNT is a positive integer
if ! [[ "${COMPONENT_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: COMPONENT_COUNT must be a positive integer (got: '${COMPONENT_COUNT}')" >&2
    exit 1
fi

# ============================================================================
# IMAGE STRATEGY: Consume an Image List Only
# ============================================================================
#
# This generator consumes an image list file and produces a Snapshot manifest.
# It does not build images or validate them against the registry.
#
# Typical inputs:
# - component names (resolved to `:stable` in the target namespace)
# - full image refs with tags or digests
#
# ============================================================================

# Configuration
FRESH_BUILDS_FILE="${FRESH_BUILDS_FILE:-/tmp/fresh-images-pool.txt}"

# Verify fresh builds file exists
if [ -z "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: FRESH_BUILDS_FILE environment variable not set" >&2
    echo "" >&2
    echo "Provide a file containing component names or image references." >&2
    echo "" >&2
    exit 1
fi

if [ ! -f "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: Fresh builds file not found: ${FRESH_BUILDS_FILE}" >&2
    echo "" >&2
    echo "Provide a valid file path in FRESH_BUILDS_FILE." >&2
    echo "" >&2
    exit 1
fi

# Read image pool from fresh builds file
declare -a IMAGE_POOL=()
while IFS= read -r line; do
    # Allow comments/blank lines in static lists
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -z "${line}" ] && continue

    IMAGE_POOL+=("${line}")
done < "${FRESH_BUILDS_FILE}"

POOL_SIZE=${#IMAGE_POOL[@]}

# Validate pool has images
if [ ${POOL_SIZE} -eq 0 ]; then
    echo "❌ Error: No images found in ${FRESH_BUILDS_FILE}" >&2
    echo "   The image pool file is empty or contains no valid images" >&2
    exit 1
fi

echo "📦 Using image pool file" >&2
echo "   Source: ${FRESH_BUILDS_FILE}" >&2
echo "   Entries: ${POOL_SIZE}" >&2

# Limit COMPONENT_COUNT to available images in pool
if [ ${COMPONENT_COUNT} -gt ${POOL_SIZE} ]; then
    echo "⚠️  Requested ${COMPONENT_COUNT} components but only ${POOL_SIZE} images available" >&2
    echo "   Limiting snapshot to ${POOL_SIZE} components" >&2
    COMPONENT_COUNT=${POOL_SIZE}
fi

# Also limit to 200 components for snapshot (even if more images available)
MAX_SNAPSHOT_COMPONENTS=200
ACTUAL_COMPONENT_COUNT=${COMPONENT_COUNT}
if [ ${COMPONENT_COUNT} -gt ${MAX_SNAPSHOT_COMPONENTS} ]; then
    echo "⚠️  Limiting snapshot to ${MAX_SNAPSHOT_COMPONENTS} components (found ${COMPONENT_COUNT} images)" >&2
    COMPONENT_COUNT=${MAX_SNAPSHOT_COMPONENTS}
fi

echo "Generating large snapshot with ${COMPONENT_COUNT} components..." >&2
echo "" >&2

# Convert one entry from the pool into a concrete container image reference.
# Supported formats:
# - component name: v4-15-apiserver-watcher-01
# - repo path: quay.io/.../component  (tagless)
# - full image ref: quay.io/.../component:tag or quay.io/.../component@sha256:...
resolve_container_image() {
    local entry="$1"

    # If entry is a bare component name, build the target image ref in the test namespace.
    if [[ "${entry}" != *"/"* ]]; then
        echo "quay.io/redhat-user-workloads-stage/${NAMESPACE}/${entry}:stable"
        return 0
    fi

    # If entry already contains a digest or tag, use it as-is.
    if [[ "${entry}" == *"@sha256:"* ]] || [[ "${entry}" == *":"* ]]; then
        echo "${entry}"
        return 0
    fi

    # Otherwise treat it as a repo path and default to :stable.
    echo "${entry}:stable"
    return 0
}

extract_component_name() {
    local image_ref="$1"
    local name="${image_ref##*/}"   # after last /
    name="${name%%@*}"              # strip @sha256...
    name="${name%%:*}"              # strip :tag
    echo "${name}"
}

# Resolve a tag-based image reference to its digest
# Input: quay.io/repo/image:stable
# Output: quay.io/repo/image@sha256:abcd...
resolve_tag_to_digest() {
    local image_ref="$1"
    
    # If already a digest reference, return as-is
    if [[ "${image_ref}" == *"@sha256:"* ]]; then
        echo "${image_ref}"
        return 0
    fi
    
    # If it's a tag reference, resolve to digest using skopeo
    if [[ "${image_ref}" == *":"* ]]; then
        echo "   Resolving ${image_ref} to digest..." >&2
        
        local digest
        digest=$(skopeo inspect "docker://${image_ref}" --format '{{.Digest}}' 2>&1)
        
        if [ $? -ne 0 ]; then
            echo "❌ Error: Failed to resolve ${image_ref} to digest" >&2
            echo "   ${digest}" >&2
            return 1
        fi
        
        # Convert tag reference to digest reference
        local repo="${image_ref%:*}"  # Remove :tag
        echo "${repo}@${digest}"
        return 0
    fi
    
    # No tag or digest, return as-is
    echo "${image_ref}"
    return 0
}

cat <<EOF
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Snapshot
metadata:
  name: "${SNAPSHOT_NAME}"
  namespace: "${NAMESPACE}"
  labels:
    test.appstudio.openshift.io/type: "large-snapshot"
    test.appstudio.openshift.io/component-count: "${COMPONENT_COUNT}"
    appstudio.openshift.io/application: "${APPLICATION_NAME}"
  annotations:
    test.appstudio.openshift.io/description: "Large snapshot with ${COMPONENT_COUNT} components for rh-advisories pipeline testing (using actual component names from images)"
    test.appstudio.openshift.io/available-images: "${ACTUAL_COMPONENT_COUNT}"
    # Skip build since we're using pre-built container images
    test.appstudio.openshift.io/skip-build: "true"
    # Skip idempotency to allow re-testing with the same snapshot data
    # Expected behavior: Release can proceed even if this exact snapshot was released before
    # Rationale: This is a test snapshot with static pre-built images for scale testing
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  application: "${APPLICATION_NAME}"
  displayName: "Large Snapshot - ${COMPONENT_COUNT} Components"
  displayDescription: "Test snapshot with ${COMPONENT_COUNT} components using actual component names for large-scale release testing"
  artifacts: {}
  components:
EOF

for (( i=1; i<=COMPONENT_COUNT; i++ )); do
    # Use different images from the pool for variety
    IMAGE_INDEX=$(((i - 1) % ${#IMAGE_POOL[@]}))
    TAGGED_IMAGE="$(resolve_container_image "${IMAGE_POOL[$IMAGE_INDEX]}")"
    
    # Resolve tag to digest (required by apply-mapping task)
    CONTAINER_IMAGE="$(resolve_tag_to_digest "${TAGGED_IMAGE}")"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to resolve image for component ${i}" >&2
        exit 1
    fi
    
    # Extract actual component name from image URL
    COMPONENT_NAME="$(extract_component_name "${CONTAINER_IMAGE}")"
    
    # Use the actual source repository that components were built from
    # This matches the attestations created during PAC builds
    SOURCE_URL="https://github.com/hacbs-release-tests/e2e-base"
    
    # Generate component entry
    cat <<EOF
    - name: "${COMPONENT_NAME}"
      containerImage: "${CONTAINER_IMAGE}"
      source:
        git:
          url: "${SOURCE_URL}"
          revision: "main"
EOF
done

echo "" >&2
echo "✅ Snapshot manifest generated successfully" >&2
echo "   Snapshot name: ${SNAPSHOT_NAME}" >&2
echo "   Application: ${APPLICATION_NAME}" >&2
echo "   Namespace: ${NAMESPACE}" >&2
echo "   Components: ${COMPONENT_COUNT}" >&2
echo "" >&2
echo "To apply this snapshot:" >&2
echo "  ./generate-large-snapshot.sh ${SNAPSHOT_NAME} ${APPLICATION_NAME} ${NAMESPACE} ${COMPONENT_COUNT} | kubectl apply -f -" >&2
