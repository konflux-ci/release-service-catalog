#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a dummy charon aws crendentials secret (and delete it first if it exists)
aws_creds=$(cat <<- EOF
[test]
aws_user = SENSITIVE_DATA_test-user
aws_access_key_id = SENSITIVE_DATA_justadummykey
aws_secret_access_key = SENSITIVE_DATA_justadummyaccesskey
region = SENSITIVE_DATA_us-east-1
EOF
)
kubectl delete secret test-charon-aws-credentials --ignore-not-found
kubectl create secret generic test-charon-aws-credentials --from-literal=credentials="$aws_creds"

kubectl delete secret test-ca --ignore-not-found
kubectl create secret generic test-ca \
  --from-literal=client-key.pem="SENSITIVE_DATA_testkey" \
  --from-literal=client-key.password="SENSITIVE_DATA_testpass" \
  --from-literal=mrrc-signing.crt="SENSITIVE_DATA_testca"

# Add mocks to the beginning of scripts
# Step 0: use-trusted-artifact (ref - no script)
# Step 1: prepare-repo (script)
# Step 2: upload-single-maven-zip (script)
# Step 3: merge-multiple-maven-zips (script)
# Step 4: push-merged-maven-repo-to-registry (script)
# Step 5: upload-merged-maven-zip (script)
# Step 6: create-trusted-artifact (ref - no script)
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[1].script' "$TASK_PATH"
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[2].script' "$TASK_PATH"
yq -i '.spec.steps[3].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[3].script' "$TASK_PATH"
yq -i '.spec.steps[4].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[4].script' "$TASK_PATH"
yq -i '.spec.steps[5].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[5].script' "$TASK_PATH"
