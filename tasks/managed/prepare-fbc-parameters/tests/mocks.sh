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
    # Read what bundle images were actually requested from the internal-request call
    requested_bundles=""
    if [ -f "$(params.dataDir)/mock_internal-request.txt" ]; then
      requested_bundles=$(sed -n 's/.*containerImages=\(\[.*\]\).*/\1/p' \
        "$(params.dataDir)/mock_internal-request.txt" || echo "")
    fi

    # Determine which bundle images to return based on what was requested
    if echo "$requested_bundles" | grep -q "operator-foundry-e2e-example-operator-bundle"; then
      # Test with operator-foundry bundles (integration test with modified component-2)
      echo '{"optInResults": [{"containerImage": "quay.io/joelanford/example-operator-bundle:0.1.0", "fbcOptIn": true}, {"containerImage": "quay.io/joelanford/example-operator-bundle:0.2.0", "fbcOptIn": true}, {"containerImage": "quay.io/exd-guild-hello-operator/operator-foundry-e2e-example-operator-bundle:0.1.0", "fbcOptIn": true}, {"containerImage": "quay.io/exd-guild-hello-operator/operator-foundry-e2e-example-operator-bundle:0.2.0", "fbcOptIn": true}]}'
    elif [ -f "$(params.dataDir)/data.json" ] && grep -q "non-matching-package" "$(params.dataDir)/data.json"; then
      # Failure propagation test (package validation will fail)
      echo '{"optInResults": [{"containerImage": "quay.io/joelanford/example-operator-bundle:0.1.0", "fbcOptIn": true}, {"containerImage": "quay.io/joelanford/example-operator-bundle:0.2.0", "fbcOptIn": true}]}'
    else
      # Default case: return opt-in for all known test bundle images
      # This handles both integration test (2 components) and duplicate packages test (4 components with duplicates)
      # The actual bundles from the test images (sha256:f6e7... and sha256:4218...)
      echo '{"optInResults": [{"containerImage": "quay.io/joelanford/example-operator-bundle:0.1.0", "fbcOptIn": true}, {"containerImage": "quay.io/joelanford/example-operator-bundle:0.2.0", "fbcOptIn": true}]}'
    fi
  else
    # Forward other kubectl calls to the real command
    /usr/bin/kubectl "$@"
  fi
}

# Export functions so they're available to the task scripts
export -f internal-request
export -f kubectl
