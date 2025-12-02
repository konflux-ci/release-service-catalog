#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function kinit() {
  echo "kinit $*"
}

function curl() {
  echo Mock curl called with: $* >&2

  if [[ "$*" == "--retry 3 --negotiate -u : myurl/auth/token" ]]
  then
    echo '{"access": "dummy-token"}'
  elif [[ "$*" == *"myurl/osidb/api/v2/flaws?cve_id=CVE-embargo"* ]]
  then
    echo '{"results": [{"embargoed": true}]}'
  elif [[ "$*" == *"myurl/osidb/api/v2/flaws?cve_id=CVE-noaccess"* ]]
  then
    echo '{}'
  elif [[ "$*" == *"myurl/osidb/api/v2/flaws?cve_id="* ]]
  then
    echo '{"results": [{"embargoed": false}]}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}

# The external script won't see these functions unless we export them
export -f kinit
export -f curl
