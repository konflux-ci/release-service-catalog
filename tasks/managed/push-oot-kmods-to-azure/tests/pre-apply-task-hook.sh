#!/usr/bin/env bash

set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Injecting test scripts into Task: $TASK_PATH"

echo "Neutralizing StepAction at spec.steps[0]..."

# Create the mock step script that includes test setup
cat > /tmp/mock-setup-script.sh <<EOF
#!/usr/bin/env sh
echo "Mocked use-trusted-artifact step. Setting up test data..."
mkdir -p /var/workdir/release
cd /var/workdir/release

$(cat "$SCRIPT_DIR/test-setup.sh")
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

echo "Injecting mock/check scripts into spec.steps[2]..."
MOCK_SCRIPT=$(cat "$SCRIPT_DIR/mocks.sh")

ORIG_SCRIPT=$(yq '.spec.steps[2].script' "$TASK_PATH" | sed '1s|^#!/.*||')

CHECK_SCRIPT="
echo 'Running final mock assertions...'
check_upload_count
"

cat > /tmp/injected-script.sh <<EOF
#!/usr/bin/env bash
# This is the new, combined script for testing

# --- Injected Mock Script (defines functions) ---
$MOCK_SCRIPT

# --- Original Task Script (shebang removed) ---
$ORIG_SCRIPT

# --- Injected Check Script (runs assertions) ---
$CHECK_SCRIPT
EOF

yq -i '.spec.steps[2].script = load_str("/tmp/injected-script.sh")' "$TASK_PATH"
rm /tmp/injected-script.sh

echo "Injection complete. Creating Azure mock secret..."

kubectl delete secret azure-mock-secret --ignore-not-found
kubectl create secret generic azure-mock-secret \
  --from-literal=AZURE_TENANT_ID=mock-tenant-id \
  --from-literal=AZURE_CLIENT_ID=mock-client-id \
  --from-literal=AZURE_CLIENT_SECRET=mock-client-secret