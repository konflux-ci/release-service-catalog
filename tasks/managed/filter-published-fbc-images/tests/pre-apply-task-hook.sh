#!/usr/bin/env bash
set -euo pipefail

kubectl delete secret pyxis --ignore-not-found
kubectl create secret generic pyxis \
  --from-literal=cert="mock-cert" \
  --from-literal=key="mock-key"
