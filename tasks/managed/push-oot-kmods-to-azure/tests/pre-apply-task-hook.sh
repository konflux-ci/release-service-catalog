#!/usr/bin/env bash

set -euo pipefail

echo "Creating Azure mock secret..."

kubectl delete secret azure-mock-secret --ignore-not-found
kubectl create secret generic azure-mock-secret \
  --from-literal=AZURE_TENANT_ID=mock-tenant-id \
  --from-literal=AZURE_CLIENT_ID=mock-client-id \
  --from-literal=AZURE_CLIENT_SECRET=mock-client-secret
