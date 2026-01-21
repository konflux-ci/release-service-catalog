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

  if [[ "$*" == \
    *"python3 lib/dummy-collector.py --test-arg test-value --release /workspace/data/release.json --previousRelease \
/workspace/data/previous_release.json tenant" ]]
  then
    echo '{"name": "dummy", "example-argument": "test-value", "issues": ["RELEASE-1", "RELEASE-2"]}'
    return
  fi

  if [[ "$*" == \
    *"python3 lib/parallel-collector.py --test-arg test-value --release /workspace/data/release.json \
--previousRelease /workspace/data/previous_release.json tenant" ]]
  then
    date +%s >> $(workspaces.data.path)/parallel-time.txt
    sleep 5
    echo '{"name": "dummy", "example-argument": "test-value", "issues": ["RELEASE-1", "RELEASE-2"]}'
    date +%s >> $(workspaces.data.path)/parallel-time.txt
    return
  fi

  if [[ "$*" == \
    *"python3 lib/timeout-collector.py --test-arg test-value --release /workspace/data/release.json \
--previousRelease /workspace/data/previous_release.json tenant" ]]
  then
    exit 124 # timeout exits 124 if it times out
  fi

  # KONFLUX-11658: Test for template interpolation
  # Use pattern matching to handle bash quoting of arguments with spaces
  if [[ "$*" == *'lib/interpolation-collector.py'* ]] && \
     [[ "$*" == *'--query'*'project = TEST AND fixVersion = "2.1.1"'* ]] && \
     [[ "$*" == *'--static-arg'*'no-template-here'* ]]
  then
    echo '{"name": "interpolation-test", "interpolated_query": "project = TEST AND fixVersion = \"2.1.1\""}'
    return
  fi

  echo Error: Unexpected call
  exit 1
}
