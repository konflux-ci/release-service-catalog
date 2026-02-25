#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests for this pipeline only to avoid conflicts
kubectl delete internalrequests \
  -l "internal-services.appstudio.openshift.io/pipelinerun-uid" \
  --timeout=30s || true

# Add mocks to the beginning of task step scripts
# Step 1 (prepare-inputs) needs date mock for timestamp generation and timeout calculation
# Step 2 (process-ocp-groups) needs internal-request, set_ir_status, and date mocks
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
