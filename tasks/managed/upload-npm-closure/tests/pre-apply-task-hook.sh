#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="upload-npm-closure-test-credentials"
kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=username=test-user \
  --from-literal=password=test-password \
  --dry-run=client -o yaml | kubectl apply -f -

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
  echo 'npm-release-closure-update'
} > "${wrapped}"

yq -i '
  (.spec.steps[] | select(.name == "closure-update")) |=
    (del(.command) | .script = load_str("'"${wrapped}"'"))
' "${TASK_PATH}"
