#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"

# Create dummy secrets for UMB and Pyxis (and delete them first if they exist)
kubectl delete secret umb-ssl-cert --ignore-not-found
kubectl create secret generic umb-ssl-cert --from-literal=cert=SENSITIVE_DATA_myumbcert --from-literal=key=SENSITIVE_DATA_myumbkey

kubectl delete secret pyxis-ssl-cert --ignore-not-found
kubectl create secret generic pyxis-ssl-cert --from-literal=cert=SENSITIVE_DATA_mypyxiscert --from-literal=key=SENSITIVE_DATA_mypyxiskey

