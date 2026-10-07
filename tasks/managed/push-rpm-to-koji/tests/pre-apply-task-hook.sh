#!/usr/bin/env bash
set -euo pipefail

# Delete existing secrets if they exist
kubectl delete secret push-koji-test --ignore-not-found

# Create the fake secrets for koji
kubectl create secret generic push-koji-test \
  --from-literal=base64_keytab="$(base64 <<< "some keytab")"
