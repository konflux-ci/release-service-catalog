#!/usr/bin/env bash
set -eux

TASK_PATH=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks into the filter-already-released-images step (step index 1).
# Step 0 (use-trusted-artifact) and step 2 (create-trusted-artifact) use StepAction
# refs and have no script field, so they must not be touched.
yq -i '.spec.steps[1].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create mock Pyxis credentials secret (kept for compatibility with any residual references)
kubectl create secret generic pyxis \
  --from-literal=cert="mock-cert" \
  --from-literal=key="mock-key" \
  --dry-run=client -o yaml | kubectl apply -f - || true
