#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
curl() {
  # Output the call to stderr
  echo "Mock curl called with:" "$@" >&2
  workdir="$(params.dataDir)/$(params.subdirectory)/workdir"
  echo "$@" >> "$workdir/mock_curl.txt"

  # Throw a failure (which should be caught) for Atlas API calls in the curl fail test
  params="$*"
  # A command uploading the "spdx_minimal_curl_fail_2_3" SBOM to Atlas should fail
  if [[ "$params" =~ "https://atlas.release.devshift.net/api/v2/sbom" && "$params" =~ "spdx_minimal_curl_fail_2_3" ]]; then
    return 1
  fi
}
