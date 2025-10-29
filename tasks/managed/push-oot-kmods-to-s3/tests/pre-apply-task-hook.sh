#!/usr/bin/env bash

set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Injecting test scripts into Task: $TASK_PATH"

echo "Neutralizing StepAction at spec.steps[0] and injecting setup script..."

SETUP_SCRIPT_CONTENT=$(cat "$SCRIPT_DIR/test-setup.sh")
cat > /tmp/mock-setup-script.sh <<EOF
#!/usr/bin/env sh
echo "Mocked use-trusted-artifact step. Running setup script..."

# --- Injected Setup Script ---
(
$SETUP_SCRIPT_CONTENT
)
EOF

cat > /tmp/mock-step.yaml <<EOF
name: use-trusted-artifact-mock
image: alpine:latest
script: "placeholder"
EOF

yq -i '.script = load_str("/tmp/mock-setup-script.sh")' /tmp/mock-step.yaml
rm /tmp/mock-setup-script.sh

yq -i '.spec.steps[0] = load("/tmp/mock-step.yaml")' "$TASK_PATH"
rm /tmp/mock-step.yaml

echo "Injecting mock/check scripts into spec.steps[1]..."
MOCK_SCRIPT=$(cat "$SCRIPT_DIR/mocks.sh")
ORIG_SCRIPT=$(yq '.spec.steps[1].script' "$TASK_PATH" | sed '1s|^#!/.*||')

CHECK_SCRIPT="
echo 'Running final mock assertions...'
check_final_status
"

cat > /tmp/injected-script.sh <<EOF
#!/usr/bin/env sh
# This is the new, combined script for testing

# --- Injected Mock Script (defines functions) ---
$MOCK_SCRIPT

# --- Original Task Script (shebang removed) ---
$ORIG_SCRIPT

# --- Injected Check Script (runs assertions) ---
$CHECK_SCRIPT
EOF

yq -i '.spec.steps[1].script = load_str("/tmp/injected-script.sh")' "$TASK_PATH"
rm /tmp/injected-script.sh

echo "Injection complete. Creating S3 mock secret..."

kubectl delete secret s3-mock-secret --ignore-not-found
kubectl create secret generic s3-mock-secret \
  --from-literal=aws_access_key_id=MOCK_AWS_KEY_ID \
  --from-literal=aws_secret_access_key=MOCK_AWS_SECRET_KEY