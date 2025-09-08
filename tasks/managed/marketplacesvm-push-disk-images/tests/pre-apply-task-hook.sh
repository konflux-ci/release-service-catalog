#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy secret (and delete it first if it exists)
kubectl delete secret marketplacesvm-test-secret --ignore-not-found
kubectl create secret generic marketplacesvm-test-secret --from-literal=key=eyJ0ZXN0Ijoic2VjcmV0In0K
