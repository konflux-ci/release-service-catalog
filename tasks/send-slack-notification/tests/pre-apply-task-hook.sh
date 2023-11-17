#!/usr/bin/env bash

set -x
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' $SCRIPT_DIR/../send-slack-notification.yaml

# Create a dummy slack-notification-secret secret (and delete it first if it exists)
kubectl delete secret my-secret --ignore-not-found

kubectl create secret generic my-secret --from-literal=my-team=ABCDEF
