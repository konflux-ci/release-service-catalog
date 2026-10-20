#!/usr/bin/env bash
set -eux

# Mock for the bash upload-sboms-to-atlas step. Injected by pre-apply-task-hook.sh.
# Named mocks_upload.sh (not mocks.sh) so test_tekton_tasks.sh does not wrap the
# Python extract step, which needs no mocks.

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
