#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create a dummy configmap with a valid self-signed certificate (and delete it first if it exists)
kubectl delete configmap test-use-custom-ca-cert --ignore-not-found

# Generate a valid self-signed certificate for testing
# oras tool needs a valid PEM format certificate, not just a string
CERT_FILE=$(mktemp)
openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$CERT_FILE" \
  -days 1 -subj "/CN=test-ca" 2>/dev/null

kubectl create configmap test-use-custom-ca-cert --from-file=cert="$CERT_FILE"
rm -f "$CERT_FILE"
