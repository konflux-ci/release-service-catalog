#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a dummy charon aws crendentials secret (and delete it first if it exists)
aws_creds=$(cat <<- EOF
[test]
aws_user = test-user
aws_access_key_id = THIS_SHOULD_NOT_BE_EXPOSED
aws_secret_access_key = THIS_SHOULD_NOT_BE_EXPOSED
region = us-east-1
EOF
)
kubectl delete secret test-charon-aws-credentials --ignore-not-found
kubectl create secret generic test-charon-aws-credentials --from-literal=credentials="$aws_creds"

kubectl delete secret test-ca --ignore-not-found
kubectl create secret generic test-ca \
  --from-literal=client-key.pem="THIS_SHOULD_NOT_BE_EXPOSED" \
  --from-literal=client-key.password="THIS_SHOULD_NOT_BE_EXPOSED" \
  --from-literal=mrrc-signing.crt="THIS_SHOULD_NOT_BE_EXPOSED"

# Add mocks to the beginning of scripts
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
