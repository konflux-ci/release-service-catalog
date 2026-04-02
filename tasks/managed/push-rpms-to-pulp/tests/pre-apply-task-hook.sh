#!/usr/bin/env bash

set -x
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Mount mocks as ConfigMap and source them instead of prepending to the step script.
# This avoids "argument list too long" from Tekton's place-scripts when the combined script is large.
kubectl delete configmap test-mocks --ignore-not-found
kubectl create configmap test-mocks --from-file=mocks.sh="$SCRIPT_DIR/mocks.sh"
yq -i '.spec.volumes += [{"name": "test-mocks", "configMap": {"name": "test-mocks"}}]' "$TASK_PATH"
yq -i '.spec.steps[1].volumeMounts += [{"name": "test-mocks", "mountPath": "/mnt/test-mocks"}]' "$TASK_PATH"
yq -i '.spec.steps[1].script |= sub("^(#![^\n]*\n)", "${1}source /mnt/test-mocks/mocks.sh\n")' "$TASK_PATH"

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=cli.toml='base_url = "https://console.redhat.com"
client_id = "mock-client-id"
client_secret = "mock-client-secret"
'

# Create a dummy pulp secret for basic auth (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret-basic --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret-basic --from-literal=cli.toml='base_url = "https://console.redhat.com"
username = "mock-user"
password = "mock-password"
'

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret-missing --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret-missing --from-literal=dummy=abcdef123
