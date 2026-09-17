#!/usr/bin/env bash

kubectl delete secret rhtl-pulp-credentials-secret --ignore-not-found
kubectl create secret generic rhtl-pulp-credentials-secret \
  --from-literal=username=test-user \
  --from-literal=password=test-password

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Prepend mocks to the 'publish' step (index 2) script so the mocked pulp
# shadows the real binary. This step already uses `script`, so concatenate.
# Steps layout:
#   [0] prepare-workdir (command - no mock needed)
#   [1] use-trusted-artifact (StepAction ref - no mock needed)
#   [2] publish (script - prepend mocks)
#   [3] create-trusted-artifact (StepAction ref - no mock needed)
EXISTING=$(yq '.spec.steps[2].script' "$TASK_PATH")
EXISTING="$EXISTING" yq -i '.spec.steps[2].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + "\n" + strenv(EXISTING)' \
  "$TASK_PATH"
