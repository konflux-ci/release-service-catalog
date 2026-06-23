#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
curl-with-retry() {
  echo "Mock curl-with-retry called with:" "$@" >&2
  echo "$@" >> "$(params.dataDir)/mock_curl.txt"
  if [[ "$*" =~ fail-catalog ]]; then
    echo "API rate limit exceeded" >&2
    return 1
  fi
  echo '{ "sha": "12345"}'
}
