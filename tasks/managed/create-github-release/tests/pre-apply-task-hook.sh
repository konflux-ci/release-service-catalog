#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="${1}"

# Bind port 443 for the in-pod mock without running as root (test task copy only).
yq -i \
  '.spec.steps[1].securityContext.capabilities = {"add": ["NET_BIND_SERVICE"]}' \
  "${TASK_PATH}"

# Create a dummy github secret (and delete it first if it exists)
kubectl delete secret test-create-github-release-token --ignore-not-found
kubectl create secret generic test-create-github-release-token --from-literal=token=mytoken
