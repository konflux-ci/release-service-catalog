#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests to avoid conflicts and ensure clean test state
echo "=== Cleaning up old InternalRequests (pre-apply-task-hook) ==="

# Show what exists before cleanup
echo "InternalRequests before cleanup:"
kubectl get internalrequests -o custom-columns=\
NAME:.metadata.name,PIPELINE-UID:.metadata.labels."internal-services\.appstudio\.openshift\.io/pipelinerun-uid",\
BATCH:.metadata.labels.batch-number,OCP:.metadata.labels.ocp-version 2>/dev/null || echo "None found"

# Delete test-specific InternalRequests only (safe for shared namespaces)
echo "Deleting test InternalRequests (safe for shared namespace)..."

# Only delete IRs with test-specific labels
echo "  Deleting IRs with group-id label (test IRs)..."
kubectl delete internalrequests \
  -l "internal-services.appstudio.openshift.io/group-id" \
  --timeout=30s 2>/dev/null || true

echo "  Deleting IRs with pipelinerun-uid label (test IRs)..."
kubectl delete internalrequests \
  -l "internal-services.appstudio.openshift.io/pipelinerun-uid" \
  --timeout=30s 2>/dev/null || true

# Also delete by name pattern (update-fbc-catalog) as fallback
echo "  Deleting remaining update-fbc-catalog IRs..."
kubectl get internalrequests -o name 2>/dev/null | \
  grep "update-fbc-catalog" | \
  xargs -r kubectl delete --timeout=30s 2>/dev/null || true

# Give k8s time to fully clean up resources and finalizers
echo "  Waiting for cleanup to complete..."
sleep 3

# Verify cleanup (only check labeled IRs, not all)
echo "InternalRequests after cleanup:"
echo "  With group-id label:"
kubectl get internalrequests -l "internal-services.appstudio.openshift.io/group-id" \
  --no-headers 2>/dev/null || echo "    None"
echo "  With pipelinerun-uid label:"
kubectl get internalrequests -l "internal-services.appstudio.openshift.io/pipelinerun-uid" \
  --no-headers 2>/dev/null || echo "    None"

echo "InternalRequest cleanup completed"

# Clean up OCI Trusted Artifacts to prevent data contamination between tests
echo "=== Cleaning up OCI Trusted Artifacts ==="

# The registry stores artifacts at registry-service.kind-registry/trusted-artifacts
# Since the registry has no persistent storage, we can restart it to clear all artifacts
# This prevents tests from accidentally loading artifacts from previous tests

if kubectl get deployment registry -n kind-registry &>/dev/null; then
  echo "Restarting registry deployment to clear cached artifacts..."
  
  # Restart the registry by deleting the pod (deployment will recreate it)
  kubectl delete pods -n kind-registry -l run=registry --timeout=30s || true
  
  # Wait for new pod to be ready
  echo "Waiting for registry to be ready..."
  for i in {1..30}; do
    if kubectl get pods -n kind-registry -l run=registry --field-selector=status.phase=Running &>/dev/null && \
       kubectl wait --for=condition=ready pod -l run=registry -n kind-registry --timeout=2s &>/dev/null; then
      echo "✅ Registry restarted and ready"
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "⚠️  WARNING: Registry restart timed out - artifacts from previous tests may persist"
    fi
    sleep 1
  done
else
  echo "Registry deployment not found - skipping artifact cleanup"
fi

echo "=== Pre-apply-task-hook cleanup finished ==="

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
