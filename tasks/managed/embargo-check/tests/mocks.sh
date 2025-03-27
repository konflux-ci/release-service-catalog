#!/usr/bin/env bash
set -x

# mocks to be injected into task step scripts
function curl-with-retry() {
  echo Mock curl called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  if [[ "$*" == "--retry 3 https://jira.atlassian.com/rest/api/2/issue/ISSUE-123" ]]
  then
    :
  elif [[ "$*" == "--retry 3 https://bugzilla.redhat.com/rest/bug/12345" ]]
  then
    :
  elif [[ "$*" == "--retry 3 https://jira.atlassian.com/rest/api/2/issue/EMBARGOED-987" ]]
  then
    exit 1
  elif [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/MISSINGRH-123" ]]
  then
    exit 1
  elif [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/FEATURE-123" ]] # Not a Vulnerability
  then
    echo '{"fields":{"issuetype":{"name":"Feature"},"security":"a"}}'
  elif [[ "$*" == *"Authorization: Bearer"*"https://issues.redhat.com/rest/api/2/issue/CVE-123" ]] # Vulnerability
  then
    echo '{"fields":{"issuetype":{"name":"Vulnerability"},"customfield_12324749":"CVE-123","customfield_12324752":"my-component","security":"a"}}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/PUBLIC-1" ]] # Public: no security field, works without auth
  then
    echo '{"fields":{"foo":"bar"}}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/PRIVATE-1" ]] # Private: no security field, works with auth but not without
  then
    if [[ "$*" == *"Authorization: Bearer"* ]] ; then
      :
    else
      return 1
    fi
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/PRIVATE-2" ]] # Private: has security field
  then
    echo '{"fields":{"security":"bar"}}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}

function internal-request() {
  if [[ "$*" == *"CVE-999"* ]]; then
    echo "InternalRequest 'embargo-ir' created."
  elif [[ "$*" == *"CVE-FAIL-555"* ]]; then
    exit 1
  else
    echo "InternalRequest 'success-ir' created."
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
