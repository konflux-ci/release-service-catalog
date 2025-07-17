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
  # Return success for SSO token requests and S3 uploads, but fail for Atlas API calls
  if [[ "$params" =~ "https://auth.redhat.com/auth/realms/EmployeeIDP/protocol/openid-connect/token" ]]; then
    echo '{"access_token":"fake_token","expires_in":3600}'
    return 0
  elif [[ "$params" =~ "AWS" ]]; then
    return 0
  elif [[ "$params" =~ "GET" && "$params" =~ "/api/v2/sbom" ]]; then
    # Check if this is for the idempotent test (by checking if identifier contains "existing-sbom")
    if [[ "$params" =~ "existing-sbom" ]]; then
      # Mock GET request to check if SBOM exists - return result indicating SBOM exists
      echo '{"total":1,"results":[{"id":"existing-sbom-id","documentNamespace":"http://spdx.org/spdxdocs/existing-sbom"}]}'
      return 0
    else
      # Mock GET request to check if SBOM exists - return empty result (SBOM doesn't exist)
      echo '{"total":0,"results":[]}'
      return 0
    fi
  else
    return 1
  fi
}
