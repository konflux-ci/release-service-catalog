#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function git() {
  echo Mock git called with: $*
  echo $* >> $(workspaces.data.path)/mock_git.txt

  if [[ "$*" == "clone "* ]]
  then
    mkdir collectors
    return
  fi

  echo Error: Unexpected git call
  exit 1
}

function timeout() {
  echo Mock timeout called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_timeout.txt

  if [[ "$*" == *"python3 dummy-collector --test-arg test-value" ]]
  then
    echo '{"name": "dummy", "example-argument": "test-value", "issues": ["RELEASE-1", "RELEASE-2"]}'
    return
  fi

  echo Error: Unexpected call
  exit 1
}
