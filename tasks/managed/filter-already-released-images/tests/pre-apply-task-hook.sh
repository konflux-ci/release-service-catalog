#!/usr/bin/env bash
set -eux

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "PRE-APPLY: Creating test secrets"
kubectl delete secret test-pyxis-secret --ignore-not-found
kubectl create secret generic test-pyxis-secret --from-literal=cert=mycert --from-literal=key=mykey
kubectl delete secret test-gitlab-secret --ignore-not-found
kubectl create secret generic test-gitlab-secret --from-literal=token=mytoken

echo "PRE-APPLY: Starting injection"
echo "PRE-APPLY: SCRIPT_DIR=$SCRIPT_DIR"
echo "PRE-APPLY: TASK_PATH=$TASK_PATH"

# Extract the original script from the main filtering step
ORIGINAL_SCRIPT=$(yq '.spec.steps[] | select(.name == "filter-already-released-images") | .script' "$TASK_PATH")
echo "PRE-APPLY: Original script extracted (${#ORIGINAL_SCRIPT} chars)"

# Concatenate mocks.sh with the original script
INJECTED_SCRIPT=$(cat "$SCRIPT_DIR/mocks.sh")$'\n'"$ORIGINAL_SCRIPT"
echo "PRE-APPLY: Combined script created (${#INJECTED_SCRIPT} chars)"

# Export for yq strenv()
export INJECTED_SCRIPT

# Update the task with the combined script
yq -i '(.spec.steps[] | select(.name == "filter-already-released-images") | .script) = strenv(INJECTED_SCRIPT)' "$TASK_PATH"

echo "PRE-APPLY: Injection complete"
