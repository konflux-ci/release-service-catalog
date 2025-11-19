#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to both detect-architectures and extract-kmods steps
# The task structure is:
# step[0]: use-trusted-artifact
# step[1]: detect-architectures (where get-image-architectures is called)
# step[2]: extract-kmods (where skopeo is called)

# Add environment variable to pass snapshot parameter to mocks
yq -i '.spec.steps[1].env += [{"name": "SNAPSHOT_NAME", "value": "$(params.snapshot)"}]' "$TASK_PATH"
yq -i '.spec.steps[2].env += [{"name": "SNAPSHOT_NAME", "value": "$(params.snapshot)"}]' "$TASK_PATH"

# Inject mocks into the detect-architectures step (step[1])
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Inject mocks into the extract-kmods step (step[2])
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
