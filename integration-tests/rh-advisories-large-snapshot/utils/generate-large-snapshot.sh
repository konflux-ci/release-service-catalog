#!/usr/bin/env bash
#
# generate-large-snapshot.sh - Utility to generate a large snapshot manifest
#
# This script creates a Snapshot CR with approximately 200 components
# for testing the rh-advisories pipeline with large-scale data.
#
# Usage:
#   ./generate-large-snapshot.sh <snapshot-name> <application-name> <namespace> [component-count]
#
# Arguments:
#   snapshot-name      : Name for the snapshot
#   application-name   : Name of the application
#   namespace          : Kubernetes namespace
#   component-count    : Number of components (default: 200)
#
# Output:
#   Writes snapshot YAML to stdout
#
# Example:
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
# IMAGE POOL STRATEGY: Dynamic Generation with Caching
# ============================================================================
# 
# Generates a pool of 200 diverse public images from quay.io for 200 components
# - Uses generate-image-pool.sh to dynamically discover accessible images
# - Caches results in /tmp/image-pool-200.txt for fast subsequent runs
# - First run: ~5 minutes (generates pool with 200 images)
# - Subsequent runs: instant (uses cache)
# - 1:1 ratio: Each of 200 components gets a unique image
#
# Image sources (200 verified accessible quay.io images):
# - Konflux CI: release-service-utils (50+ SHAs), appstudio-utils (50+ SHAs)
# - Konflux CI: release-service (11), mintmaker (11), integration-service (9)
# - Konflux CI: build-service (11)
# - Public base images: CentOS, Fedora, AlmaLinux, Rocky Linux, ArchLinux
# - Build tools: Podman, Skopeo, Buildah (multiple versions)
#
# Benefits:
# - Self-updating: automatically includes new image versions as they're published
# - Maintainable: no hardcoded lists to update
# - Efficient: caching makes subsequent runs instant
# - Diverse: discovers all accessible public images
# - Consistent: same 200 images used across all test runs
#
# Limitations (acceptable for scale testing):
# - No SBOM support (public images don't have Tekton Chains SBOMs)
# - No signature verification (EC policy has signature checks excluded)
# - Atlas/Mobster disabled (would fail attestation verification anyway)
#
# ============================================================================

# Configuration
POOL_CACHE_FILE="/tmp/image-pool-200.txt"
POOL_GENERATOR="$(dirname "$0")/generate-image-pool.sh"
TARGET_POOL_SIZE=200

# Generate image pool if cache doesn't exist (hybrid approach for CI/CD)
if [ ! -f "${POOL_CACHE_FILE}" ]; then
    echo "🔄 Image pool cache not found, generating pool of ${TARGET_POOL_SIZE} images..." >&2
    echo "   (This will take ~2 minutes on first run, then be cached)" >&2
    echo "" >&2
    
    if [ ! -f "${POOL_GENERATOR}" ]; then
        echo "❌ Error: Image pool generator not found at ${POOL_GENERATOR}" >&2
        exit 1
    fi
    
    # Generate the pool (outputs to POOL_CACHE_FILE)
    if ! "${POOL_GENERATOR}" "${TARGET_POOL_SIZE}" "${POOL_CACHE_FILE}"; then
        echo "❌ Error: Failed to generate image pool" >&2
        exit 1
    fi
    echo "" >&2
else
    echo "✅ Using cached image pool from ${POOL_CACHE_FILE}" >&2
fi

# Read image pool from cache file
declare -a IMAGE_POOL=()
mapfile -t IMAGE_POOL < "${POOL_CACHE_FILE}"

# Note: PR_CONTAINER_IMAGE support removed - using only the 200 diverse public images
# This ensures consistent behavior across all test runs without dependency on PR-specific images

POOL_SIZE=${#IMAGE_POOL[@]}
echo "" >&2
echo "📦 Image pool: ${POOL_SIZE} images (1:1 ratio with ${COMPONENT_COUNT} components)" >&2

echo "Generating large snapshot with ${COMPONENT_COUNT} components..." >&2
echo "" >&2

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
    test.appstudio.openshift.io/description: "Large snapshot with ${COMPONENT_COUNT} components for rh-advisories pipeline testing"
    # Skip build since we're using pre-built container images
    test.appstudio.openshift.io/skip-build: "true"
    # Skip idempotency to allow re-testing with the same snapshot data
    # Expected behavior: Release can proceed even if this exact snapshot was released before
    # Rationale: This is a test snapshot with static pre-built images for scale testing
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  application: "${APPLICATION_NAME}"
  displayName: "Large Snapshot - ${COMPONENT_COUNT} Components"
  displayDescription: "Test snapshot with ${COMPONENT_COUNT} components for large-scale release testing"
  artifacts: {}
  components:
EOF

for (( i=1; i<=COMPONENT_COUNT; i++ )); do
    COMPONENT_NUMBER=$(printf "%03d" "$i")
    COMPONENT_NAME="component-${COMPONENT_NUMBER}"
    
    # Use different images from the pool for variety
    IMAGE_INDEX=$(((i - 1) % ${#IMAGE_POOL[@]}))
    CONTAINER_IMAGE="${IMAGE_POOL[$IMAGE_INDEX]}"
    
    # Add some variation in the source URLs
    if (( i % 10 == 0 )); then
        SOURCE_URL="https://github.com/hacbs-release-tests/large-snapshot-test-alt"
    else
        SOURCE_URL="https://github.com/hacbs-release-tests/large-snapshot-test"
    fi
    
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
