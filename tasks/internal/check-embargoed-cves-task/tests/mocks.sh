#!/usr/bin/env sh
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

# The retry script won't see the kinit function unless we export it
export -f kinit
