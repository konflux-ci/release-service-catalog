#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function gh() {
  echo "Mock gh called with: $*" >&2
  echo "$*" >> "$(params.dataDir)/mock_gh.txt"
  if [[ "$*" == "api repos/foo/repo_with_release/releases"* ]]; then
    echo "{"repodata": "lotsofdata"}"
    exit 0
  elif
    [[ "$*" == "release create v1.2.3 ./foo.zip ./foo.json ./foo_SHA256SUMS ./foo_SHA256SUMS.sig --repo https://github.com/foo/bar --title Release 1.2.3" ]] || \
    [[ "$*" == "api repos/foo/bar/releases"* ]]; then
    exit 0
  else
    echo Error: Unexpected call
    exit 1
  fi
}
