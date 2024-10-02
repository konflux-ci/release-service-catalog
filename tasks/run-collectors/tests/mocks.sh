#!/usr/bin/env bash
set -xeo pipefail

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

  if [[ "$*" == *"python3 parallel-collector --test-arg test-value" ]]
  then
    date +%s >> $(workspaces.data.path)/parallel-time.txt
    sleep 5
    echo '{"name": "dummy", "example-argument": "test-value", "issues": ["RELEASE-1", "RELEASE-2"]}'
    date +%s >> $(workspaces.data.path)/parallel-time.txt
    return
  fi

  if [[ "$*" == *"python3 timeout-collector --test-arg test-value" ]]
  then
    exit 124 # timeout exits 124 if it times out
  fi

  echo Error: Unexpected call
  exit 1
}
