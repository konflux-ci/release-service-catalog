#!/usr/bin/env bash
set -euo pipefail

# Validate required argument
if [ $# -ne 1 ]; then
  echo "Error: Missing required argument TASK_PATH" >&2
  echo "Usage: $0 <path-to-task.yaml>" >&2
  exit 1
fi

TASK_PATH="$1"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Validate TASK_PATH exists
if [ ! -f "${TASK_PATH}" ]; then
  echo "Error: Task file not found: ${TASK_PATH}" >&2
  exit 1
fi

# Add mocks to the beginning of the filter step script (standard approach)
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create test secrets (delete first if they exist)
kubectl delete secret pyxis --ignore-not-found
kubectl create secret generic pyxis \
  --from-literal=cert="mock-cert" \
  --from-literal=key="mock-key"
