#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks.sh into the task's first step
yq -i '.spec.steps[1].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Add RBAC so that the SA executing the tests can retrieve configMap
kubectl apply -f .github/resources/crd_rbac.yaml

# Create a configMap with the schema to be used by the task
kubectl delete configmap check-data-keys-schema --ignore-not-found
kubectl create configmap check-data-keys-schema --from-file=dataKeys="$SCRIPT_DIR/../../../../schema/dataKeys.json"
