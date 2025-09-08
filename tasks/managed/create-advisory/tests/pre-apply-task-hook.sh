#!/usr/bin/env bash

# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"

yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mock_generic_type_advisories.sh") + .spec.steps[1].script' "$TASK_PATH"
# Create a dummy publish-to-cgw secret (and delete it first if it exists)
kubectl delete secret publish-to-cgw-secret --ignore-not-found
kubectl create secret generic publish-to-cgw-secret --from-literal=username=myusername --from-literal=token=mytoken
