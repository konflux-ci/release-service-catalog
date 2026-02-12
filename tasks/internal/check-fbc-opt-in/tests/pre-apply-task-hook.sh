#!/usr/bin/env bash

# Create the IIB service account secret (matching test parameter and upstream pattern)
kubectl create secret generic test-iib-service-account \
    --from-literal=keytab="$(echo 'SENSITIVE_DATA_fake-keytab-content' | base64)" \
    --from-literal=principal="SENSITIVE_DATA_fake-principal@REDHAT.COM" || true

# Create the iib-services-config secret
kubectl create secret generic iib-services-config \
    --from-literal=krb5.conf="[libdefaults]\n  default_realm = SENSITIVE_DATA_REDHAT.COM" \
    --from-literal=url="https://fakeiib.host" || true

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"
