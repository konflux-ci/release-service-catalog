#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create mock Atlas secret so the volume mount doesn't fail
kubectl create secret generic mock-atlas-secret \
    --from-literal=sso_account=mock-sso-account \
    --from-literal=sso_token=mock-sso-token \
    --dry-run=client -o yaml | kubectl apply -f -

# Steps layout:
#   [0] prepare-workdir (command - no mock needed)
#   [1] use-trusted-artifact (StepAction ref - no mock needed)
#   [2] extract-sboms-from-wheels (script - needs unzip mock)
#   [3] upload-sboms-to-atlas (script - needs mobster mock)

yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
yq -i '.spec.steps[3].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[3].script' "$TASK_PATH"
