#!/usr/bin/env bash

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

# Add mocks to the beginning of scripts
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
