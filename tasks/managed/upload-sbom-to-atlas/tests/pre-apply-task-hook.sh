#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[4].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[4].script' "$TASK_PATH"

# Also mock curl in S3 retry step
yq -i '.spec.steps[5].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[5].script' "$TASK_PATH"

# Create a dummy Atlas secret (and delete it first if it exists)
kubectl delete secret atlas-test-sso-secret --ignore-not-found
kubectl create secret generic atlas-test-sso-secret \
    --from-literal=sso_account='a29uZmx1eC1jaQ==' \
    --from-literal=sso_token='cGFzcw=='

# Create a dummy AWS secret
kubectl delete secret retry-aws-secret --ignore-not-found
kubectl create secret generic retry-aws-secret \
    --from-literal=atlas-aws-access-key-id='a29uZmx1eC1jaQ==' \
    --from-literal=atlas-aws-secret-access-key='cGFzcw=='
