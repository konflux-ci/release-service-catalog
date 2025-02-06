#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function curl() {
  echo Mock curl called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  if [[ "$*" == *"Content-Type"*"https://issues.redhat.com/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    :
  elif [[ "$*" == *"Content-Type"*"https://issues.redhat.com/rest/api/2/issue/FAIL-999/transitions" ]]
  then
    exit 1
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    echo '{"transitions":[{"id":"91","name":"Closed","description":""},{"id":"11","name":"New"}]}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/NOCLOSE-555/transitions" ]]
  then
    exit 1
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/CLOSED-987" ]]
  then
    echo '{"fields":{"status":{"name":"Closed","id":"99"}}}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}
