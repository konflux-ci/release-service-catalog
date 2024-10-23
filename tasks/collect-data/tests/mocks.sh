#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
curl() {
  # Output the call to stderr
  echo "Mock curl called with:" "$@" >&2
  echo "$@" >> "$(workspaces.data.path)/mock_curl.txt"
  echo '{ "sha": "12345"}'
}
