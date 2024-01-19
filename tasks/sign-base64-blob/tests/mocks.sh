#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request $@ -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function kubectl() {
  if [ $* != "get internalrequest internal-request -o=jsonpath='{.status.results.signed_payload}'" ]
  then
    echo "Unexpected call to kubectl"
    exit 1
  fi

  echo -n "dummy-payload" | base64
}

function gpg() {
  echo -n "dummy-payload" 	
}
