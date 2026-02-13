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
# IMAGE STRATEGY: Fresh Konflux Builds Only
# ============================================================================
# 
# This test uses ONLY fresh Konflux builds to test worst-case signing performance:
#
# Why fresh builds?
# - Zero existing Red Hat signatures
# - Multi-arch builds: 4 architectures (amd64, arm64, s390x, ppc64le)
# - Signing tasks must sign ALL ~800 digests (200 images × 4 architectures)
# - Tests signing service capacity and bottlenecks
# - Maximum worst-case scenario
#
# Build images:
#   ./utils/build-images.sh 200 dev-release-team-tenant
#
# Or use the wrapper script:
#   ./test.sh
#
# Expected performance:
# - Build time: 15-30 minutes (200 Konflux builds)
# - Signing time: 1-2 hours (ALL digests need signing)
# - Total pipeline: 5.5-7.5 hours
#
# ============================================================================

# Configuration
FRESH_BUILDS_FILE="${FRESH_BUILDS_FILE:-/tmp/fresh-images-pool.txt}"

# Verify fresh builds file exists
if [ -z "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: FRESH_BUILDS_FILE environment variable not set" >&2
    echo "" >&2
    echo "This test requires fresh Konflux builds for worst-case signing performance." >&2
    echo "" >&2
    echo "To build images:" >&2
    echo "  ./utils/build-images.sh 200" >&2
    echo "" >&2
    echo "Or use the wrapper script:" >&2
    echo "  ./test.sh" >&2
    echo "" >&2
    exit 1
fi

if [ ! -f "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: Fresh builds file not found: ${FRESH_BUILDS_FILE}" >&2
    echo "" >&2
    echo "Run utils/build-images.sh to build components first:" >&2
    echo "  ./utils/build-images.sh 200 dev-release-team-tenant" >&2
    echo "" >&2
    echo "Or use the wrapper script:" >&2
    echo "  ./test.sh" >&2
    echo "" >&2
    exit 1
fi

# Read image pool from fresh builds file
declare -a IMAGE_POOL=()
mapfile -t IMAGE_POOL < "${FRESH_BUILDS_FILE}"

POOL_SIZE=${#IMAGE_POOL[@]}

# Validate pool has images
if [ ${POOL_SIZE} -eq 0 ]; then
    echo "❌ Error: No images found in ${FRESH_BUILDS_FILE}" >&2
    echo "   The image pool file is empty or contains no valid images" >&2
    exit 1
fi

echo "🏗️  Using fresh Konflux builds (unsigned images)" >&2
echo "   Source: ${FRESH_BUILDS_FILE}" >&2
echo "   Images: ${POOL_SIZE}" >&2

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
    CONTAINER_IMAGE="${IMAGE_POOL[$IMAGE_INDEX]}"
    
    # Extract actual component name from image URL
    # Format: quay.io/.../COMPONENT_NAME@sha256:...
    COMPONENT_NAME="${CONTAINER_IMAGE##*/}"  # Get everything after last /
    COMPONENT_NAME="${COMPONENT_NAME%%@*}"    # Remove everything after @
    
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
