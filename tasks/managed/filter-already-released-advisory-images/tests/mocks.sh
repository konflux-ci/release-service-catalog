#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    echo '{
      "result": "Success",
      "filtered_snapshot": "{\"application\":\"myapp\",\"components\":[{\"name\":\"new-component\",\"repository\":\"quay.io/redhat-pending/repo2\",\"containerImage\":\"quay.io/redhat-pending/repo2@sha256:def456\"}]}",
      "internalRequestPipelineRunName": "test-pipeline-run",
      "internalRequestTaskRunName": "test-task-run"
    }'
  else
    /usr/bin/kubectl "$@"
  fi
}
