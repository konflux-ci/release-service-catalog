#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    echo '{"result":"Success","advisory_url":"https://access.redhat.com/errata/RHBA-2025:1111"}'
  else
    /usr/bin/kubectl $*
  fi
}
