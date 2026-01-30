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

# Parse arguments
SNAPSHOT_NAME="${1:-large-snapshot}"
APPLICATION_NAME="${2:-test-app}"
NAMESPACE="${3:-dev-release-team-tenant}"
COMPONENT_COUNT="${4:-200}"

# Base image to use for all components
# Using a stable, pre-built image from registry.redhat.io
BASE_IMAGE="registry.redhat.io/openshift4/ose-cli:latest"

# Alternative images for variety (optional)
declare -a IMAGE_POOL=(
    "registry.redhat.io/openshift4/ose-cli:latest"
    "registry.redhat.io/ubi8/ubi-minimal:latest"
    "registry.redhat.io/ubi9/ubi-minimal:latest"
    "registry.redhat.io/rhel8/support-tools:latest"
)

echo "Generating large snapshot with ${COMPONENT_COUNT} components..."
echo ""

# Generate snapshot header
cat <<EOF
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Snapshot
metadata:
  name: ${SNAPSHOT_NAME}
  namespace: ${NAMESPACE}
  labels:
    test.appstudio.openshift.io/type: large-snapshot
    test.appstudio.openshift.io/component-count: "${COMPONENT_COUNT}"
    appstudio.openshift.io/application: ${APPLICATION_NAME}
  annotations:
    test.appstudio.openshift.io/description: "Large snapshot with ${COMPONENT_COUNT} components for rh-advisories pipeline testing"
    test.appstudio.openshift.io/skip-build: "true"
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  application: ${APPLICATION_NAME}
  displayName: "Large Snapshot - ${COMPONENT_COUNT} Components"
  displayDescription: "Test snapshot with ${COMPONENT_COUNT} components for large-scale release testing"
  artifacts: {}
  components:
EOF

# Generate components
for i in $(seq 1 "${COMPONENT_COUNT}"); do
    COMPONENT_NUMBER=$(printf "%03d" $i)
    COMPONENT_NAME="component-${COMPONENT_NUMBER}"
    
    # Use different images from the pool for variety
    IMAGE_INDEX=$((i % ${#IMAGE_POOL[@]}))
    CONTAINER_IMAGE="${IMAGE_POOL[$IMAGE_INDEX]}"
    
    # Add some variation in the source URLs
    if [ $((i % 10)) -eq 0 ]; then
        SOURCE_URL="https://github.com/hacbs-release-tests/large-snapshot-test-alt"
    else
        SOURCE_URL="https://github.com/hacbs-release-tests/large-snapshot-test"
    fi
    
    # Generate component entry
    cat <<EOF
    - name: ${COMPONENT_NAME}
      containerImage: ${CONTAINER_IMAGE}
      source:
        git:
          url: ${SOURCE_URL}
          revision: main
EOF

    # Add some components with additional metadata for realism
    if [ $((i % 20)) -eq 0 ]; then
        cat <<EOF
      repository: quay.io/redhat-pending/rhtap----${COMPONENT_NAME}
EOF
    fi
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
