#!/usr/bin/env bash
set -euo pipefail

# Wrap the extract command step so bash mocks (oras/cosign) are visible to
# npm-release-extract and its child scripts via export -f.
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
  echo 'npm-release-extract'
} > "${wrapped}"

yq -i '
  (.spec.steps[] | select(.name == "extract")) |=
    (del(.command) | .script = load_str("'"${wrapped}"'"))
' "${TASK_PATH}"
