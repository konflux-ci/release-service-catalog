#!/bin/bash

TASK_PATH=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create test registry token secret for the tests
kubectl create secret generic test-registry-token \
  --from-literal=token="fake-token-for-testing" \
  --dry-run=client -o yaml | kubectl apply -f - || true

# Inject mocks into the update-trusted-tasks step (step[1])
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' $TASK_PATH

# Inject mocks into the make-data-acceptable-bundles-public step (step[2])
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' $TASK_PATH
