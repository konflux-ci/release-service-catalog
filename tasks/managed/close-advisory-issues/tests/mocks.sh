#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function curl-with-retry() {
  echo Mock curl called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  if [[ "$*" == *"Content-Type"*"https://issues.redhat.com/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    :
  elif [[ "$*" == *"Content-Type"*"https://issues.redhat.com/rest/api/2/issue/FAIL-999/transitions" ]]
  then
    return 1
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/FAIL-999/transitions" ]]
  then
    echo '{"transitions":[{"id":"91","name":"Closed","description":""},{"id":"11","name":"New"}]}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    echo '{"transitions":[{"id":"91","name":"Closed","description":""},{"id":"11","name":"New"}]}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/NOCLOSE-555/transitions" ]]
  then
    echo '{"expand":"transitions","transitions":[]}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/CLOSED-987" ]]
  then
    echo '{"fields":{"status":{"name":"Closed","id":"99"}}}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/FAIL-999/comment" ]]
  then
    echo '{}'
  elif [[ "$*" == *"https://issues.redhat.com/rest/api/2/issue/NOCLOSE-555/comment" ]]
  then
    echo '{}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}
