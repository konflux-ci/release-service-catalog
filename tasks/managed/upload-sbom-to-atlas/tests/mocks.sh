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
  else
    return 1
  fi
}
