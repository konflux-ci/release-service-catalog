#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function gh() {
  echo "Mock gh called with: $*"
  echo "$*" >> $(workspaces.data.path)/mock_gh.txt

  if [[ "$*" != "release create v1.2.3 foo.zip foo.json foo_SHA256SUMS foo_SHA256SUMS.sig --repo foo/bar --title Release 1.2.3" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}
