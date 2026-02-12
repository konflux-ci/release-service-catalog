#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"

# Create a dummy secret (and delete it first if it exists)
kubectl delete secret publish-index-image-secret --ignore-not-found
kubectl create secret generic publish-index-image-secret --from-literal=sourceIndexCredential=SENSITIVE_DATA_source --from-literal=targetIndexCredential=SENSITIVE_DATA_target
