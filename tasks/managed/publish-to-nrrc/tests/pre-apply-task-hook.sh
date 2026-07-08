#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a dummy charon aws crendentials secret (and delete it first if it exists)
aws_creds=$(cat <<- EOF
[test]
aws_user = test-user
aws_access_key_id = justadummykey
aws_secret_access_key = justadummyaccesskey
region = us-east-1
EOF
)
kubectl delete secret test-charon-aws-credentials --ignore-not-found
kubectl create secret generic test-charon-aws-credentials --from-literal=credentials="$aws_creds"

kubectl delete secret test-ca --ignore-not-found
kubectl create secret generic test-ca \
  --from-literal=client-key.pem="testkey" \
  --from-literal=client-key.password="testpass" \
  --from-literal=mrrc-signing.crt="testca"

kubectl delete configmap test-use-custom-ca-cert --ignore-not-found
kubectl create configmap test-use-custom-ca-cert --from-literal=cert=mycert

# Python entrypoint mocks are merged from tests/mocks.yaml and tests/mocks/ by
# test_tekton_tasks.sh (see CONTRIBUTING.md).
#
# Bash script steps need mocks injected via yq prepend.
# Step 0: use-trusted-artifact (ref - no script)
# Step 1: prepare-repo (Python entrypoint - uses mocks.yaml)
# Step 2: upload-npm-archive (bash script - needs yq mock injection)
# Step 3: create-trusted-artifact (ref - no script)
yq -i '.spec.steps[2].script = load_str("'"$SCRIPT_DIR"'/mocks_upload.sh") + .spec.steps[2].script' "$TASK_PATH"
