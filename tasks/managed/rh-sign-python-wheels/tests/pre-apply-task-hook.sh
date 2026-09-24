#!/usr/bin/env bash

# Create a dummy AWS KMS secret (and delete it first if it exists)
kubectl delete secret test-aws-kms-secret --ignore-not-found
kubectl create secret generic test-aws-kms-secret \
  --from-literal=AWS_DEFAULT_REGION=us-east-1 \
  --from-literal=AWS_ACCESS_KEY_ID=test-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=test-secret-key \
  --from-literal=SIGN_KEY=awskms:///arn:aws:kms:us-east-1:123456789:key/test-key

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

