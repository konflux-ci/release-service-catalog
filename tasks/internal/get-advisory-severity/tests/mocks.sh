#!/usr/bin/env sh
set -exo pipefail

# mocks to be injected into task step scripts

function kinit() {
  echo "kinit $*"
}

function curl() {
  echo Mock curl called with: $* >&2

  if [[ "$*" == "--retry 3 --negotiate -u : myurl/auth/token" ]]
  then
    echo '{"access": "dummy-token"}'
  elif [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-critical"* ]]
  then
    echo '{"results": [{"impact":"CRITICAL","affects":[{"purl":"pkg:oci/kubernetes?repository_url=component&a=b","impact":""}]}]}'
  elif [[ "$*" == *"myurl/osidb/api/v1/flaws?cve_id=CVE-moderate"* ]]
  then
    echo '{"results": [{"impact":"MODERATE","affects":[{"purl":"pkg:oci/kubernetes?repository_url=foo&a=b","impact":"LOW"},{"purl":"pkg:oci/kubernetes?repository_url=component&a=b","impact":"IMPORTANT"},{"purl":"","impact":"LOW"}]}]}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}
