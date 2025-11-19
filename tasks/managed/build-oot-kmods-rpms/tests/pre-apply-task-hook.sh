#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of the build-rpm-packages step script (step[1])
# The task has steps: 0=use-trusted-artifact, 1=build-rpm-packages, 2=create-trusted-artifact
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "\n\n" + .spec.steps[1].script' "$TASK_PATH"