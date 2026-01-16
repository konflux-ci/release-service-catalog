#!/usr/bin/env bash
set -eu

# mocks to be injected into task step scripts
function curl-with-retry() {
  echo Mock curl >&2
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  if [[ "$*" == *"-u team@domain.com:abcdefg"*"Content-Type"*"https://redhat.atlassian.net/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    :
  elif [[ "$*" == *"-u team@domain.com:abcdefg"*"Content-Type"*"https://redhat.atlassian.net/rest/api/2/issue/FAIL-999/transitions" ]]
  then
    return 1
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/FAIL-999/transitions" ]]
  then
    echo '{"transitions":[{"id":"91","name":"Closed","description":""},{"id":"11","name":"New"}]}'
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/ISSUE-123/transitions" ]]
  then
    echo '{"transitions":[{"id":"91","name":"Closed","description":""},{"id":"11","name":"New"}]}'
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/NOCLOSE-555/transitions" ]]
  then
    echo '{"expand":"transitions","transitions":[]}'
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/CLOSED-987" ]]
  then
    echo '{"fields":{"status":{"name":"Closed","id":"99"}}}'
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/FAIL-999/comment" ]]
  then
    echo '{}'
  elif [[ "$*" == *"https://redhat.atlassian.net/rest/api/2/issue/NOCLOSE-555/comment" ]]
  then
    echo '{}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}
