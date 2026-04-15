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

# Mount mocks via ConfigMap and source via BASH_ENV (avoids inlining mocks into the step script)
MOCKS_CM_NAME="file-updates-task-mocks"
MOCKS_MOUNT_PATH="/workspace/mocks"
kubectl delete configmap "${MOCKS_CM_NAME}" --ignore-not-found
kubectl create configmap "${MOCKS_CM_NAME}" --from-file=mocks.sh="${SCRIPT_DIR}/mocks.sh"

yq -i '.spec.volumes += [{"name": "test-mocks", "configMap": {"name": "'"${MOCKS_CM_NAME}"'"}}]' "$TASK_PATH"
yq -i '.spec.steps[0].volumeMounts += [{"name": "test-mocks", "mountPath": "'"${MOCKS_MOUNT_PATH}"'", "readOnly": true}]' "$TASK_PATH"
yq -i '.spec.steps[0].env += [{"name": "BASH_ENV", "value": "'"${MOCKS_MOUNT_PATH}"'/mocks.sh"}]' "$TASK_PATH"

# Create test secrets (delete first if they exist)
kubectl delete secret file-updates-secret --ignore-not-found
kubectl create secret generic file-updates-secret \
  --from-literal=gitlab_host="gitlab.example.com" \
  --from-literal=gitlab_access_token="mock-token"
