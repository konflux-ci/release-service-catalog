#!/usr/bin/env bash

# Add mocks to the task step scripts
# Note: steps 0 and 3 use StepAction refs, so we only inject into steps 1 and 2
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks into the get-image-urls step (step index 1)
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Inject mocks into the extract-artifacts step (step index 2)
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
