#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
for i in `seq 0 5`; do
  yq -i '.spec.steps['$i'].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps['$i'].script' "$TASK_PATH"
done

# Create a dummy secret for ssl cert for pyxis interactions (and delete it first if it exists)
kubectl delete secret pyxis-ssl-cert --ignore-not-found
kubectl create secret generic pyxis-ssl-cert --from-literal=cert=mypyxiscert --from-literal=key=mypyxiskey

# Create a dummy secret for ssl cert for UMB interactions (and delete it first if it exists)
kubectl delete secret umb-ssl-cert --ignore-not-found
kubectl create secret generic umb-ssl-cert --from-literal=cert=myumbcert --from-literal=key=myumbkey
