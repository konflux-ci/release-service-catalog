#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function select-oci-auth() {
  echo "Mock select-oci-auth called with: $*"
  # Return empty auth
  echo '{}'
}

function retry() {
  echo "Mock retry called with: $*"
  # Just run the command without retry logic
  "$@"
}

function oras() {
  echo "Mock oras called with: $*"

  if [[ "$1" == "pull" ]]; then
    # Find the output directory from -o flag
    output_dir=""
    next_is_output=false
    for arg in "$@"; do
      if [[ "$next_is_output" == true ]]; then
        output_dir="$arg"
        next_is_output=false
      elif [[ "$arg" == "-o" ]]; then
        next_is_output=true
      fi
    done

    if [[ -n "$output_dir" ]]; then
      # Create mock Python package files
      echo "mock wheel content" > "${output_dir}/test_package-1.0.0-py3-none-any.whl"
      echo "mock sdist content" > "${output_dir}/test_package-1.0.0.tar.gz"
      echo "Created mock files in ${output_dir}"
    fi
    return 0
  fi

  return 0
}

function cosign() {
  echo "Mock cosign called with: $*" >&2

  if [[ "$1" == "verify-attestation" ]]; then
    # Real cosign verify-attestation outputs a DSSE envelope with a base64-encoded payload.
    # The payload decodes to the in-toto Statement containing predicateType and predicate
    local statement='{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"https://slsa.dev/provenance/v1","subject":[{"name":"test","digest":{"sha256":"abc123"}}],"predicate":{"buildDefinition":{"buildType":"https://tekton.dev/chains/v2/slsa","externalParameters":{"runSpec":{"pipelineRef":{"name":"build-python-wheels-oci-ta"},"params":[{"name":"PACKAGES","value":["test_package==1.0.0"]}]}},"internalParameters":{},"resolvedDependencies":[{"uri":"git+https://github.com/calungaproject/index.git","digest":{"sha1":"abc123def456"}}]},"runDetails":{"builder":{"id":"https://konflux-ci.dev/chains/v2"},"metadata":{"invocationId":"calunga-tenant/build-run-mock","startedOn":"2026-02-19T21:40:00Z","finishedOn":"2026-02-19T21:51:09Z"}}}}'
    local payload
    payload=$(echo -n "${statement}" | base64 -w0)
    echo "{\"payloadType\":\"application/vnd.in-toto+json\",\"payload\":\"${payload}\",\"signatures\":[{\"keyid\":\"\",\"sig\":\"mock-signature\"}]}"
    return 0
  fi

  return 0
}

