#!/usr/bin/env bash
set -euo pipefail

# Task-local secret name so parallel suite runs do not race on a shared Secret.
SECRET_NAME="upload-npm-pulp-test-credentials"
kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=username=test-user \
  --from-literal=password=test-password \
  --dry-run=client -o yaml | kubectl apply -f -

# Wrap the upload command step so bash HTTP mocks (export -f curl) are visible
# to npm-release-upload → npm-pulp-upload.
# Select by step name so reordering Task steps does not break the harness.
TASK_PATH="${1}"
SCRIPT_DIR="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
MOCKS="${SCRIPT_DIR}/mocks.sh"

wrapped="$(mktemp)"
trap 'rm -f "${wrapped}"' EXIT

{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  sed -e '1{/^#!/d;}' -e '/^set -euo pipefail$/d' "${MOCKS}"
  echo
  echo 'npm-release-upload'
} > "${wrapped}"

yq -i '
  (.spec.steps[] | select(.name == "upload")) |=
    (del(.command) | .script = load_str("'"${wrapped}"'"))
' "${TASK_PATH}"
