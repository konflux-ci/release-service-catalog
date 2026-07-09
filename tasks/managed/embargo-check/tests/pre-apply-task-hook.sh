#!/usr/bin/env bash
set -euo pipefail

# Create a dummy Jira access token secret
kubectl delete secret test-jira-secret --ignore-not-found
kubectl create secret generic test-jira-secret --from-literal=token=abcdefg --from-literal=email=team@domain.com
