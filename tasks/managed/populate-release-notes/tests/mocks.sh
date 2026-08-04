#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function get-image-architectures() {
    if [[ "$1" == *"dual"* ]]; then
        # Dual-compression index: get-image-architectures dedups to the gzip entry per arch
        echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "sha256:amd64gzip"}'
        echo '{"platform":{"architecture": "s390x", "os": "linux"}, "digest": "sha256:s390gzip"}'
    else
        echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "sha256:abcdefg"}'
        echo '{"platform":{"architecture": "s390x", "os": "linux"}, "digest": "sha256:deadbeef"}'
    fi
}

function curl-with-retry() {
  echo Mock curl called with: $* >&2

  mkdir -p "$(params.dataDir)"
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  if [[ "$*" == *"-u "*"https://redhat.atlassian.net/rest/api/2/issue/VULN-123" ]]; then
    # Mock a vulnerability issue with CVE-123
    echo '{"fields":{"issuetype":{"name":"Vulnerability"},"customfield_10667":"CVE-123"}}'
  elif [[ "$*" == *"-u "*"https://redhat.atlassian.net/rest/api/2/issue/FEATURE-456" ]]; then
    # Mock a non-vulnerability issue
    echo '{"fields":{"issuetype":{"name":"Feature"}}}'
  elif [[ "$*" == *"-u "*"https://redhat.atlassian.net/rest/api/2/issue/VULN-MISSING-456" ]]; then
    # Mock a vulnerability issue with CVE that should be missing from content
    echo '{"fields":{"issuetype":{"name":"Vulnerability"},"customfield_10667":"CVE-MISSING-456"}}'
  else
    echo Error: Unexpected curl call: $*
    exit 1
  fi
}
