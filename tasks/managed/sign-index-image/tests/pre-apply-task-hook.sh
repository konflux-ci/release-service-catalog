#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-create-pyxis-image-cert --ignore-not-found
kubectl create secret generic test-create-pyxis-image-cert --from-literal=cert=mycert --from-literal=key=mykey

# Create signing-config-map ConfigMap required by sign-index-image task
kubectl delete configmap signing-config-map --ignore-not-found
kubectl create configmap signing-config-map \
  --from-literal=SIG_KEY_NAME=test-signing-key

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
