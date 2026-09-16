#!/usr/bin/env bash

kubectl delete secret osidb-keytab-secret --ignore-not-found
kubectl create secret generic osidb-keytab-secret --from-literal=keytab=dummy

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Prepend mocks to the 'generate' step (index 2) script so mocked oras/slan-cuan
# shadow the real binaries. This step already uses `script`, so concatenate.
# Steps layout:
#   [0] prepare-workdir (command - no mock needed)
#   [1] use-trusted-artifact (StepAction ref - no mock needed)
#   [2] generate (script - prepend mocks)
#   [3] create-trusted-artifact (StepAction ref - no mock needed)
EXISTING=$(yq '.spec.steps[2].script' "$TASK_PATH")
EXISTING="$EXISTING" yq -i '.spec.steps[2].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + "\n" + strenv(EXISTING)' \
  "$TASK_PATH"
