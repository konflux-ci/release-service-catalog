#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy secret for ssl cert for pyxis interactions (and delete it first if it exists)
kubectl delete secret pyxis-ssl-cert --ignore-not-found
kubectl create secret generic pyxis-ssl-cert --from-literal=cert=mypyxiscert --from-literal=key=mypyxiskey

# Create a dummy secret for ssl cert for UMB interactions (and delete it first if it exists)
kubectl delete secret umb-ssl-cert --ignore-not-found
kubectl create secret generic umb-ssl-cert --from-literal=cert=myumbcert --from-literal=key=myumbkey
