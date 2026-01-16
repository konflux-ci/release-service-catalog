#!/usr/bin/env bash
set -eu

# mocks to be injected into task step scripts

function curl() {
  echo "Mock curl"
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  if [[ "$*" != "-H Content-type: application/json --data-binary @/tmp/release.json SENSITIVE_DATA_ABCDEF"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

}
