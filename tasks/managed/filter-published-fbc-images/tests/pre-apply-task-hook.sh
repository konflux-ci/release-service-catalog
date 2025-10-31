#!/usr/bin/env bash
set -eux

TASK_PATH=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks into the setup-pyxis-cert step (step index 1)
yq -i '.spec.steps[1].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Inject mocks into the filter-already-released-images step (step index 2)
yq -i '.spec.steps[2].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"

# Create mock Pyxis credentials secret for testing (not used in tests, but kept for reference)
kubectl create secret generic pyxis \
  --from-literal=cert="mock-cert" \
  --from-literal=key="mock-key" \
  --dry-run=client -o yaml | kubectl apply -f - || true
