#!/usr/bin/env bash

# Create a dummy service account secret (and delete it first if it exists)
kubectl delete secret rhtl-pulp-credentials-secret --ignore-not-found
kubectl create secret generic rhtl-pulp-credentials-secret \
  --from-literal=username=test-user \
  --from-literal=password=test-password

# Add mocks to the upload step script
# Note: step 0 uses StepAction ref, so we only inject into step 1 (upload)
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# The upload step is step index 1 and uses command, not script
# We need to replace the command with a script that includes mocks
yq -i '
  del(.spec.steps[1].command) |
  .spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh")
' "$TASK_PATH"
