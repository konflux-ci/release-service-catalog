#!/usr/bin/env bash
set -euo pipefail

# Inject DATA_DIR env var into the sign-index-image step so the internal-request
# mock can write its output to a location shared with the check-result step.
yq -i '.spec.steps[1].env += [{"name": "DATA_DIR", "value": "$(params.dataDir)"}]' "$1"

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-create-pyxis-image-cert --ignore-not-found
kubectl create secret generic test-create-pyxis-image-cert --from-literal=cert=mycert --from-literal=key=mykey
