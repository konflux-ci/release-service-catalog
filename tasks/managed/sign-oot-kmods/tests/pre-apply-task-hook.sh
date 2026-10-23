#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "Neutralizing StepAction at spec.steps[0]..."

SETUP_SCRIPT="$(mktemp)"
MOCK_STEP="$(mktemp)"
trap 'rm -f "${SETUP_SCRIPT}" "${MOCK_STEP}"' EXIT

# Build the mock script with cat so Tekton $(params.*) in test-setup.sh stay literal.
{
  echo '#!/usr/bin/env sh'
  echo 'echo "Mocked use-trusted-artifact step. Setting up test data..."'
  cat "${SCRIPT_DIR}/test-setup.sh"
} > "${SETUP_SCRIPT}"

cat > "${MOCK_STEP}" <<'EOF'
name: use-trusted-artifact-mock
image: alpine:latest
script: "placeholder"
EOF

yq -i ".script = load_str(\"${SETUP_SCRIPT}\")" "${MOCK_STEP}"
yq -i ".spec.steps[0] = load(\"${MOCK_STEP}\")" "${TASK_PATH}"

kubectl delete secret my-mocked-secret --ignore-not-found
kubectl create secret generic my-mocked-secret \
  --from-literal=signHost=mysigning.mock.com \
  --from-literal=signKey=my-mock-signing-key \
  --from-literal=signUser=my-mock-keytab-user
echo -e "\0005\0002\c" > my-mock.keytab
echo "1.2.3.4 my-mock-host" > checksumFingerprint
kubectl delete secret build-and-sign-keytab --ignore-not-found
kubectl create secret generic build-and-sign-keytab \
  --from-file=keytab-build-and-sign.keytab=my-mock.keytab
kubectl delete secret checksum-fingerprint --ignore-not-found
kubectl create secret generic checksum-fingerprint --from-file=checksumFingerprint
