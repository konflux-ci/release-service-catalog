#!/usr/bin/env bash

set -euo pipefail

echo "Creating git token secret..."
kubectl delete secret git-token-mock --ignore-not-found
kubectl create secret generic git-token-mock \
  --from-literal=gitlab-gr-maintenance-token=mock-token
