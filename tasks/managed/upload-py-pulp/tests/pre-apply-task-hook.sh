#!/usr/bin/env bash

# Create a dummy service account secret (and delete it first if it exists)
kubectl delete secret rhtl-pulp-credentials-secret --ignore-not-found
kubectl create secret generic rhtl-pulp-credentials-secret \
  --from-literal=username=test-user \
  --from-literal=password=test-password

# Add mocks to the upload step script
# Steps layout:
#   [0] prepare-workdir (command - no mock needed)
#   [1] use-trusted-artifact (StepAction ref - no mock needed)
#   [2] upload (command - replace with mock script)
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# The upload step is step index 2 and uses command, not script
# We need to replace the command with a script that includes mocks
yq -i '
  del(.spec.steps[2].command) |
  .spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh")
' "$TASK_PATH"
