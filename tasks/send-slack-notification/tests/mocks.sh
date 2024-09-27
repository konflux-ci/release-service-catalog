#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function curl() {
  echo Mock curl called with: $*
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  if [[ "$*" != "-H Content-type: application/json --data-binary @/tmp/release.json ABCDEF"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

}
