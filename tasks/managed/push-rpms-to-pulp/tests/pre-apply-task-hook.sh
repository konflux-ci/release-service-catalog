#!/usr/bin/env bash

set -x
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
#
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=cli.toml='base_url = "https://console.redhat.com"
client_id = "mock-client-id"
client_secret = "mock-client-secret"
'

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret-missing --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret-missing --from-literal=dummy=abcdef123
