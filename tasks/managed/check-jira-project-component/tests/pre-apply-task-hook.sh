#!/usr/bin/env bash
set -euo pipefail

# Create a dummy Jira secret (delete it first if it exists). The task mounts this
# secret and reads the 'email' and 'token' keys for basic authentication.
kubectl delete secret test-check-jira-project-component-secret --ignore-not-found
kubectl create secret generic test-check-jira-project-component-secret \
  --from-literal=email="svc-release@example.com" \
  --from-literal=token="dummy-token"
