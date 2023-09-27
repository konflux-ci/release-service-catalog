#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function gh() {
  echo "Mock gh called with: $*"
  echo "$*" >> $(workspaces.data.path)/mock_gh.txt

  if [[ "$*" != "release create 1.2.3 foo.zip foo.json foo_SHA256SUMS --repo foo/bar" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}
