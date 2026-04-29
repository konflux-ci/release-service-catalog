#!/usr/bin/env bash
set -eux

MOCK_LOG="${MOCK_LOG:-/tmp/mock_calls.txt}"

function unzip() {
  echo "Mock unzip called with: $*" >&2
  echo "unzip $*" >> "${MOCK_LOG}"

  if [[ "$1" == "-l" ]]; then
    local wheel="$2"
    local wheel_base
    wheel_base=$(basename "$wheel" .whl)
    cat <<LISTING
Archive:  $wheel
  Length      Date    Time    Name
---------  ---------- -----   ----
     2048  2026-04-13 10:00   ${wheel_base}.dist-info/sboms/sbom.spdx.json
---------                     -------
     2048                     1 file
LISTING
    return 0
  fi

  if [[ "$1" == "-p" ]]; then
    cat <<'SBOM'
{"spdxVersion":"SPDX-2.3","dataLicense":"CC0-1.0","SPDXID":"SPDXRef-DOCUMENT","name":"test-sbom","documentNamespace":"https://example.com/test","creationInfo":{"creators":["Organization: Red Hat"]}}
SBOM
    return 0
  fi

  echo "ERROR: unexpected unzip command: $*" >&2
  exit 1
}

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
