#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  if [[ "$*" == *"CVE-999"* ]]; then
    echo "InternalRequest 'failure-ir' created."
  else
    echo "InternalRequest 'success-ir' created."
  fi
}

function kubectl() {
  # The IR won't actually be created, so mock it to return Success as the task wants
  if [[ "$*" == *"get internalrequest success-ir"* ]]
  then
    echo '{"result":"Success","severity":"IMPORTANT"}'
  elif [[ "$*" == *"get internalrequest failure-ir"* ]]
  then
    echo '{"result":"Failure","severity":""}'
  else
    /usr/bin/kubectl $*
  fi
}
