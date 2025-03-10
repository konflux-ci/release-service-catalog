#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"

# Create a dummy AWS secret
kubectl delete secret atlas-test-aws-secret --ignore-not-found
kubectl create secret generic atlas-test-aws-secret \
    --from-literal=atlas-aws-access-key-id='a29uZmx1eC1jaQ==' \
    --from-literal=atlas-aws-secret-access-key='cGFzcw=='
