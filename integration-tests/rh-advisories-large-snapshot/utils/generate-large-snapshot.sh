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
# - Signing tasks must sign ALL ~600 digests (200 images × ~3 architectures)
# - Tests true signing service capacity and bottlenecks
# - Realistic worst-case scenario
#
# Build fresh images:
#   ./utils/build-fresh-images.sh 200 dev-release-team-tenant
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
    echo "To build fresh images:" >&2
    echo "  ./utils/build-fresh-images.sh 200" >&2
    echo "" >&2
    echo "Or use the wrapper script:" >&2
    echo "  ./test.sh" >&2
    echo "" >&2
    exit 1
fi

if [ ! -f "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: Fresh builds file not found: ${FRESH_BUILDS_FILE}" >&2
    echo "" >&2
    echo "Run utils/build-fresh-images.sh to build fresh components first:" >&2
    echo "  ./utils/build-fresh-images.sh 200 dev-release-team-tenant" >&2
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

echo "🏗️  Using fresh Konflux builds (unsigned images)" >&2
echo "   Source: ${FRESH_BUILDS_FILE}" >&2
echo "   Images: ${POOL_SIZE}" >&2

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
