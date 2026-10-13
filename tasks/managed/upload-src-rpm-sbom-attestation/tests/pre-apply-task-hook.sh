#!/usr/bin/env bash

set -euo pipefail

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=cli.toml='base_url = "https://console.redhat.com"
client_id = "mock-client-id"
client_secret = "mock-client-secret"
'
