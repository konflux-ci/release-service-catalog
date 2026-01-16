#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# create required secrets
kubectl create secret generic iib-service-account-secret \
    --from-literal=principal="SENSITIVE_DATA_iib@kerberos" \
    --from-literal=keytab="SENSITIVE_DATA_something"
kubectl create secret generic iib-services-config \
    --from-literal=krb5.conf="SENSITIVE_DATA_empty" \
    --from-literal=url="https://SENSITIVE_DTAA_fakeiib.host"

kubectl create secret generic iib-overwrite-fromimage-credentials \
    --from-literal=username="SENSITIVE_DATA_bot+user" \
    --from-literal=token="SENSITIVE_DATA_token"

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[1].script' "$TASK_PATH"
