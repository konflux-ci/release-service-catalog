#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Install the CRDs so we can create/get internalrequests
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests for this pipeline only to avoid conflicts
kubectl delete internalrequests \
  -l "internal-services.appstudio.openshift.io/pipelinerun-uid" \
  --timeout=30s || true

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script (collect-parameters step is the second step)
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"