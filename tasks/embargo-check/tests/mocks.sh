#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function curl() {
  echo Mock curl called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  if [[ "$*" == "--fail --output /dev/null https://jira.atlassian.com/rest/api/2/issue/ISSUE-123" ]]
  then
    :
  elif [[ "$*" == "--fail --output /dev/null https://bugzilla.redhat.com/rest/bug/12345" ]]
  then
    :
  elif [[ "$*" == "--fail --output /dev/null https://jira.atlassian.com/rest/api/2/issue/EMBARGOED-987" ]]
  then
    exit 1
  else
    echo Error: Unexpected call
    exit 1
  fi
}

function internal-request() {
  if [[ "$*" == *"CVE-999"* ]]; then
    echo "Name: embargo-ir"
  elif [[ "$*" == *"CVE-FAIL-555"* ]]; then
    exit 1
  else
    echo "Name: success-ir"
  fi
}

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == *"get internalrequest success-ir"* ]]
  then
    echo '{"result":"Success","embargoed_cves":""}'
  # Mock an IR with embargoed CVEs
  elif [[ "$*" == *"get internalrequest embargo-ir"* ]]
  then
    echo '{"result":"Failure","embargoed_cves":"CVE-999"}'
  else
    /usr/bin/kubectl $*
  fi
}
