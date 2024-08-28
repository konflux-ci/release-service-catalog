#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  /home/utils/internal-request "$@" -s false

  if [[ "$*" == *'snapshot_json={"application":"disk-images","components":[{"name":"failing-disk-image"'* ]]; then
      echo '{"result":"Failure"}' > $(workspaces.data.path)/mock_internal-request_result.txt
  elif [[ "$*" == *"exodusGwEnv="@(live|pre)* ]]; then
      echo '{"result":"Success"}' > $(workspaces.data.path)/mock_internal-request_result.txt
  else
      echo Unexpected call to internal-request
      exit 1
  fi
}

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    cat $(workspaces.data.path)/mock_internal-request_result.txt
  else
    /usr/bin/kubectl $*
  fi
}
