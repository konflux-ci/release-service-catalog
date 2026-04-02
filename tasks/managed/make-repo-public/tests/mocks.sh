#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function curl() {
  # Handle discovery API calls for Quay detection.
  # The real call uses -w "%{http_code}" -o /dev/null, so only the status code
  # is captured. The mock must replicate that: output just the HTTP code.
  if [[ "$*" == *'/api/v1/discovery' ]]
  then
    local url="${@: -1}"
    local registry="${url#https://}"
    registry="${registry%%/*}"
    echo Mock curl: discovery call for "$registry" >&2
    if [[ "$registry" == quay.io ]] || [[ "$registry" == self-hosted-quay.example.com* ]]
    then
      echo -n "200"
      return 0
    else
      echo -n "000"
      return 1
    fi
  fi

  echo Mock curl called with: $* >&2
  echo $* >> $(params.dataDir)/mock_curl.txt

  if [[ "$*" == *'--data {"visibility": "public"} https://'*'/api/v1/repository/'*'/changevisibility' ]]
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
