#!/usr/bin/env bash
set -euo pipefail

# Create a dummy pulp secret with basic auth so the smoke test can skip SSO.
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=cli.toml='[cli]
base_url = "http://127.0.0.1:8080"
username = "mock-user"
password = "mock-password"
'
