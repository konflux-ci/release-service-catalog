#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"

# Create a dummy exodus secret (and delete it first if it exists)
kubectl delete secret test-push-to-cdn-secret --ignore-not-found
kubectl create secret generic test-push-to-cdn-secret --from-literal=cert=mycert --from-literal=key=mykey
