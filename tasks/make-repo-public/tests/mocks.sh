#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function curl() {
  echo Mock curl called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  if [[ "$*" == '-X POST --fail-with-body --retry 3 --header Authorization: Bearer myquaytoken --header Content-Type: application/json --data {"visibility": "public"} https://quay.io/api/v1/repository/redhat-services-prod/myrepo'*'/changevisibility' ]]
  then
    if [[ "$*" == *redhat-services-prod/myrepofailing* ]]
    then
      echo Simulating failing curl >&2
      return 1
    fi
  else
    echo Error: Unexpected call
    exit 1
  fi
}
