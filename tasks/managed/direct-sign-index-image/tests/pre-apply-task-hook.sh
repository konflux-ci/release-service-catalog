#!/usr/bin/env bash
set -euo pipefail

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-pyxis-image-cert --ignore-not-found
kubectl create secret generic test-pyxis-image-cert --from-literal=cert=mycert --from-literal=key=mykey
