#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create mock Atlas secret so the volume mount doesn't fail
kubectl create secret generic mock-atlas-secret \
    --from-literal=sso_account=mock-sso-account \
    --from-literal=sso_token=mock-sso-token \
    --dry-run=client -o yaml | kubectl apply -f -

# The extract-sboms-from-wheels Python step needs no mocks: it uses stdlib
# zipfile on a real wheel created in setup. Do not add tests/mocks.yaml or
# tests/mocks.sh; test_tekton_tasks.sh would wrap that Python command if either
# file exists.
#
# Steps layout:
#   [0] use-trusted-artifact (StepAction ref - no mock needed)
#   [1] extract-sboms-from-wheels (python - no mocks)
#   [2] upload-sboms-to-atlas (script - needs mobster mock)

yq -i '.spec.steps[2].script = load_str("'"${SCRIPT_DIR}"'/mocks_upload.sh") + .spec.steps[2].script' "$TASK_PATH"
