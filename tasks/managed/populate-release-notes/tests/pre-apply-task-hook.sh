#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
yq -i '.spec.steps[3].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[3].script' "$TASK_PATH"

# Create a dummy access token secret (and delete it first if it exists)
kubectl delete secret konflux-advisory-jira-secret --ignore-not-found
kubectl create secret generic konflux-advisory-jira-secret --from-literal=token=abcdefg
