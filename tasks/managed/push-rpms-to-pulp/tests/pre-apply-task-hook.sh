#!/usr/bin/env bash

set -x
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
#
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=cli.toml='base_url = "https://SENSITIVE_DATA_console.redhat.com"
client_id = "SENSITIVE_DATA_mock-client-id"
client_secret = "SENSITIVE_DATA_mock-client-secret"
'

# Create a dummy pulp secret for basic auth (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret-basic --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret-basic --from-literal=cli.toml='base_url = "https://SENSITIVE_DATA_console.redhat.com"
username = "SENSITIVE_DATA_mock-user"
password = "SENSITIVE_DATA_mock-password"
'

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret-missing --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret-missing --from-literal=dummy=SENSITIVE_DATA_abcdef123
