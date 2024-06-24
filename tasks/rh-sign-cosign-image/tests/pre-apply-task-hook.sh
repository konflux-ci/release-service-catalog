#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# Create a dummy slack-notification-secret secret (and delete it first if it exists)
kubectl delete secret test-rh-sign-cosign-image-secret --ignore-not-found

kubectl create secret generic test-rh-sign-cosign-image-secret\
  --from-literal=AWS_REGION=us-test-1\
  --from-literal=AWS_ACCESS_KEY_ID=test-access-key\
  --from-literal=AWS_SECRET_ACCESS_KEY=test-secret-access-key

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
