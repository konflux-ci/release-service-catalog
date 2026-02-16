#!/usr/bin/env bash

# Add mocks to the task step scripts
# Steps layout:
#   [0] prepare-workdir (command - no mock needed)
#   [1] use-trusted-artifact (StepAction ref - no mock needed)
#   [2] get-image-urls (script - inject mocks)
#   [3] extract-artifacts (script - inject mocks)
#   [4] create-trusted-artifact (StepAction ref - no mock needed)
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks into the get-image-urls step (step index 2)
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"

# Inject mocks into the extract-artifacts step (step index 3)
yq -i '.spec.steps[3].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[3].script' "$TASK_PATH"
