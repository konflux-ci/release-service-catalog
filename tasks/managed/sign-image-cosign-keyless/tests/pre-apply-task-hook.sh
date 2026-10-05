#!/usr/bin/env bash
set -euo pipefail
#
# Inject PARAMS_DATA_DIR into the sign-image step (step index 1) so the mock
# binaries embedded by mocks.yaml can write call-log files to the shared data dir.
TASK_PATH="$1"
yq -i '.spec.steps[1].env += [{"name": "PARAMS_DATA_DIR", "value": "$(params.dataDir)"}]' \
    "${TASK_PATH}"
