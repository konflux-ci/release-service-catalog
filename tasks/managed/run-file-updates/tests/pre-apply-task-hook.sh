#!/usr/bin/env bash

# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# Add IR status watcher as a sidecar that patches IR statuses
# The watcher script is added as a sidecar container that runs alongside the main task
TASK_PATH="$1"
pushd -- "$( dirname -- "${BASH_SOURCE[0]}" )" > /dev/null
SCRIPT_DIR="$(pwd)"
popd > /dev/null

# Named watcher.sh, not mocks.sh: test_tekton_tasks.sh merges tests/mocks.sh into
# Python command steps and would replace the run_file_updates entrypoint.
kubectl delete configmap run-file-updates-watcher --ignore-not-found
kubectl create configmap run-file-updates-watcher --from-file=watcher.sh="${SCRIPT_DIR}/watcher.sh"

# The watcher counts fileUpdates in the task input. That count is not a Task
# parameter, so pipeline validation does not see a test-only param.
yq -i '.spec.sidecars = [
  {
    "name": "ir-watcher",
    "image": "quay.io/konflux-ci/release-service-utils@sha256:5546fa78d3c88d7b6a2e8cff8902f7757f00541d0bbaf113b9f293133894afa3",
    "script": "#!/bin/bash\nset -eux\nexec /mnt/watcher/watcher.sh",
    "env": [
      {"name": "PARAM_PIPELINE_RUN_UID", "value": "$(context.pipelineRun.uid)"},
      {"name": "PARAM_REQUEST_TIMEOUT", "value": "$(params.requestTimeout)"},
      {"name": "PARAM_DATA_DIR", "value": "$(params.dataDir)"},
      {"name": "PARAM_FILE_UPDATES_PATH", "value": "$(params.fileUpdatesPath)"},
      {"name": "PARAM_JSON_KEY", "value": "$(params.jsonKey)"}
    ],
    "volumeMounts": [
      {"name": "watcher-script", "mountPath": "/mnt/watcher"},
      {"name": "workdir", "mountPath": "/var/workdir"}
    ]
  }
]' "$TASK_PATH"

# Add volume for the watcher script
yq -i '.spec.volumes += [{"name": "watcher-script", "configMap": {"name": "run-file-updates-watcher", "defaultMode": 493}}]' "$TASK_PATH"
