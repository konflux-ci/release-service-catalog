#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy access token secret (and delete it first if it exists)
kubectl delete secret konflux-advisory-jira-secret --ignore-not-found
kubectl create secret generic konflux-advisory-jira-secret --from-literal=token=SENSITIVE_DATA_abcdefg
