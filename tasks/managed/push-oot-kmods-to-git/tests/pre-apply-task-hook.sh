#!/usr/bin/env bash

set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Injecting test scripts into Task: $TASK_PATH"

echo "Neutralizing StepAction at spec.steps[0]..."

# Create a temporary file for the setup script
SETUP_SCRIPT_CONTENT=$(cat "$SCRIPT_DIR/test-setup.sh")
cat > /tmp/mock-setup-script.sh <<EOF
#!/usr/bin/env sh
echo "Mocked use-trusted-artifact step. Running setup script..."

# --- Injected Setup Script ---
(
$SETUP_SCRIPT_CONTENT
)
EOF

# Create a base mock step YAML
cat > /tmp/mock-step.yaml <<EOF
name: use-trusted-artifact-mock
image: alpine:latest
script: "placeholder"
EOF

# Use yq load_str to safely inject the script into the mock step
yq -i '.script = load_str("/tmp/mock-setup-script.sh")' /tmp/mock-step.yaml
rm /tmp/mock-setup-script.sh

# Now, replace the task's first step with the fully formed mock step
yq -i '.spec.steps[0] = load("/tmp/mock-step.yaml")' "$TASK_PATH"
rm /tmp/mock-step.yaml


echo "Injecting mock/check scripts into spec.steps[1]..."
MOCK_SCRIPT=$(cat "$SCRIPT_DIR/mocks.sh")
ORIG_SCRIPT=$(yq '.spec.steps[1].script' "$TASK_PATH" | sed '1s|^#!/.*||')

cat > /tmp/injected-script.sh <<EOF
#!/usr/bin/env bash
# This is the new, combined script for testing

# --- Injected Mock Script (defines functions) ---
$MOCK_SCRIPT

# --- Original Task Script (shebang removed) ---
$ORIG_SCRIPT
EOF

yq -i '.spec.steps[1].script = load_str("/tmp/injected-script.sh")' "$TASK_PATH"
rm /tmp/injected-script.sh

echo "Injection complete. Creating secret..."

kubectl delete secret git-token-secret --ignore-not-found
kubectl create secret generic git-token-secret --from-literal=gitlab-gr-maintenance-token=MYVERYSECRETTOKEN