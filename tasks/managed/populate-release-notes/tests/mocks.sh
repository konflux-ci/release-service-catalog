#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function get-image-architectures() {
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "sha256:abcdefg"}'
    echo '{"platform":{"architecture": "s390x", "os": "linux"}, "digest": "sha256:deadbeef"}'
}

function curl-with-retry() {
  echo Mock curl called with: $* >&2

  mkdir -p "$(params.dataDir)"
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  if [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/VULN-123" ]]; then
    # Mock a vulnerability issue with CVE-123
    echo '{"fields":{"issuetype":{"name":"Vulnerability"},"customfield_12324749":"CVE-123"}}'
  elif [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/FEATURE-456" ]]; then
    # Mock a non-vulnerability issue
    echo '{"fields":{"issuetype":{"name":"Feature"}}}'
  elif [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/VULN-MISSING-456" ]]; then
    # Mock a vulnerability issue with CVE that should be missing from content
    echo '{"fields":{"issuetype":{"name":"Vulnerability"},"customfield_12324749":"CVE-MISSING-456"}}'
  else
    echo Error: Unexpected curl call: $*
    exit 1
  fi
}
