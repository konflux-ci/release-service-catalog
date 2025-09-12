#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # Create a mock InternalRequest name for the task to find
  echo "InternalRequest 'test-check-fbc-opt-in-ir' created."
}

function kubectl() {
  # Mock kubectl commands for internal request handling
  if [[ "$*" == "get internalrequest test-check-fbc-opt-in-ir -o jsonpath={.status.conditions[?(@.type==\"Succeeded\")].status}" ]]; then
    echo "True"
  elif [[ "$*" == "get internalrequest test-check-fbc-opt-in-ir -o jsonpath={.status.results}" ]]; then
    # Check if this is the failure propagation test based on the allowedPackages in data.json
    if [ -f "$(params.dataDir)/data.json" ] && grep -q "non-matching-package" "$(params.dataDir)/data.json"; then
      # Return mock opt-in results for failure propagation test (all opted in, but packages will fail validation)
      echo '{"optInResults": [{"containerImage": "quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component@sha256:f6e744662e342c1321deddb92469b55197002717a15f8c0b1bb2d9440aac2297", "fbcOptIn": true}]}'
    else
      # Return mock opt-in results for successful integration test
      echo '{"optInResults": [{"containerImage": "quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component@sha256:f6e744662e342c1321deddb92469b55197002717a15f8c0b1bb2d9440aac2297", "fbcOptIn": true}, {"containerImage": "quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component@sha256:f6e744662e342c1321deddb92469b55197002717a15f8c0b1bb2d9440aac2297", "fbcOptIn": true}]}'
    fi
  else
    # Forward other kubectl calls to the real command
    /usr/bin/kubectl "$@"
  fi
}

# Export functions so they're available to the task scripts
export -f internal-request
export -f kubectl
