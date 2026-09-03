#!/usr/bin/env bash
set -eux

MOCK_LOG="${MOCK_LOG:-/tmp/mock_calls.txt}"

function mobster() {
  echo "Mock mobster called with: $*" >&2
  echo "mobster $*" >> "${MOCK_LOG}"

  if [[ "$1" == "upload" && "$2" == "tpa" ]]; then
    echo "Mock upload to TPA successful" >&2
    return 0
  fi

  echo "ERROR: unexpected mobster command: $*" >&2
  exit 1
}
