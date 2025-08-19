#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of the extract-kmods step script
# The extract-kmods step is step[2] in the trusted artifacts structure
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
