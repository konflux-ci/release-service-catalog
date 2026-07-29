#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"

# Bind port 443 for the in-pod Jira mock without running as root
yq -i '(.spec.steps[] | select(.name == "populate-release-notes")).securityContext.capabilities = {"add": ["NET_BIND_SERVICE"]}' "$TASK_PATH"

# Create a dummy access token secret (and delete it first if it exists)
kubectl delete secret konflux-advisory-jira-secret --ignore-not-found
kubectl create secret generic konflux-advisory-jira-secret --from-literal=token=abcdefg --from-literal=email=team@domain.com
