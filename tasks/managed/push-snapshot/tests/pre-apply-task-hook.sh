#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy configmap (and delete it first if it exists)
kubectl delete configmap test-use-custom-ca-cert --ignore-not-found
kubectl create configmap test-use-custom-ca-cert --from-literal=cert=mycert
