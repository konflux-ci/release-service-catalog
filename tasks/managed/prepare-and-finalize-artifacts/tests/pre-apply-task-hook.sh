#!/usr/bin/env bash

set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Injecting test setup step and PATH override into Task: $TASK_PATH"

MOCK_ORAS_SCRIPT=$(cat "$SCRIPT_DIR/mocks.sh")
cat > /tmp/setup-script.sh <<EOF
#!/usr/bin/env sh
set -eux

echo "--- INJECTED SETUP STEP ---"

mkdir -p "\$(params.dataDir)"
echo "mock data" > "\$(params.dataDir)/test-data.txt"
echo "Created dummy data in \$(params.dataDir)"

cat > /var/workdir/oras <<'ORAS_MOCK_EOF'
$MOCK_ORAS_SCRIPT
ORAS_MOCK_EOF

chmod +x /var/workdir/oras
echo "Created mock oras executable at /var/workdir/oras"
echo "---------------------------"
EOF

cat > /tmp/setup-step.yaml <<EOF
- name: step-0-setup
  image: alpine:3.18
  computeResources:
    limits:
      memory: 128Mi
    requests:
      memory: 128Mi
      cpu: 100m
  script: "__PLACEHOLDER__"
EOF

yq -i '.spec.steps = load("/tmp/setup-step.yaml") + .spec.steps' "$TASK_PATH"

yq -i ".spec.steps[0].script = load_str(\"/tmp/setup-script.sh\")" "$TASK_PATH"

rm /tmp/setup-step.yaml
rm /tmp/setup-script.sh

yq -i '.spec.stepTemplate.env = [{"name": "PATH", "value": "/var/workdir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}] + .spec.stepTemplate.env' "$TASK_PATH"

echo "Injection complete."