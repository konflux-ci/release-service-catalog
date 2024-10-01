#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
curl() {
  # Output the call to stderr
  echo "Mock curl called with:" "$@" >&2
  workdir="$(workspaces.data.path)/workdir"
  echo "$@" >> "$workdir/mock_curl.txt"
}
