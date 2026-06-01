#!/usr/bin/env bash
set -euo pipefail

# Create a dummy registry secret
kubectl delete secret test-registry-secret --ignore-not-found
kubectl create secret generic test-registry-secret --from-literal=token=mock-token
