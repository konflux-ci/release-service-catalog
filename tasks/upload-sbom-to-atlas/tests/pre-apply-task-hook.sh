#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"

# Create a dummy Atlas scret (and delete it first if it exists)
kubectl delete secret atlas-test-sso-secret --ignore-not-found
kubectl create secret generic atlas-test-sso-secret --from-literal=sso_account='a29uZmx1eC1jaQ==' --from-literal=sso_token='cGFzcw=='
