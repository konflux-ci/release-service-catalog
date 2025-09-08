#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add test setup and mocks to the beginning of the push-signed-files step script (step[2])
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/test-setup.sh") + load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
kubectl delete secret repotoken --ignore-not-found
kubectl create secret generic repotoken --from-literal=gitlab-gr-maintenance-token=MYVERYSECRETTOKEN
