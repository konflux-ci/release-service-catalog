#!/usr/bin/env bash
set -euo pipefail

# mocks wrapped around the extract command step by pre-apply-task-hook.sh
#
# npm-release-extract calls npm-extract-artifacts (plumbing-utils) which
# invokes oras/select-oci-auth/retry, then populate + Chains fetch.
# Fixture .tgz files are built in the test setup step under
# ${TRUSTED_ARTIFACTS_EXTRACT_DIR}/.fixtures/.

function select-oci-auth() {
  echo "Mock select-oci-auth called with: $*"
  echo '{}'
}

function retry() {
  echo "Mock retry called with: $*"
  "$@"
}

_copy_fixture() {
  local output_dir="$1"
  local fixture_name="$2"
  local fixtures="${TRUSTED_ARTIFACTS_EXTRACT_DIR}/.fixtures"

  if [[ ! -d "${fixtures}/${fixture_name}" ]]; then
    echo "ERROR: missing fixture ${fixtures}/${fixture_name}" >&2
    return 1
  fi
  cp -a "${fixtures}/${fixture_name}/." "${output_dir}/"
  echo "Copied fixture ${fixture_name} into ${output_dir}"
}

function oras() {
  echo "Mock oras called with: $*"

  if [[ "$1" == "pull" ]]; then
    local output_dir=""
    local image=""
    local next_is_output=false
    for arg in "$@"; do
      if [[ "${next_is_output}" == true ]]; then
        output_dir="${arg}"
        next_is_output=false
      elif [[ "${arg}" == "-o" ]]; then
        next_is_output=true
      elif [[ "${arg}" == *sha256:* || "${arg}" == quay.io/* ]]; then
        image="${arg}"
      fi
    done

    if [[ -z "${output_dir}" ]]; then
      echo "ERROR: oras pull mock missing -o output dir" >&2
      return 1
    fi
    mkdir -p "${output_dir}"

    # Digest-pinned fixtures (full sha256 hex for path-safety validation):
    # …1111… → scoped package with SBOM PURL
    # …2222… → scoped package, empty SBOM (canonical PURL fallback)
    if [[ "${image}" == *sha256:1111111111111111111111111111111111111111111111111111111111111111* ]]; then
      _copy_fixture "${output_dir}" "scoped"
    elif [[ "${image}" == *sha256:2222222222222222222222222222222222222222222222222222222222222222* ]]; then
      _copy_fixture "${output_dir}" "fallback"
    else
      _copy_fixture "${output_dir}" "unscoped"
    fi
    return 0
  fi

  return 0
}

function cosign() {
  echo "Mock cosign called with: $*" >&2

  if [[ "${1}" == "verify-attestation" ]]; then
    local statement payload image="" arg digest_hex="abc123"
    for arg in "$@"; do
      if [[ "${arg}" == *sha256:* ]]; then
        image="${arg}"
        digest_hex="${image##*sha256:}"
        break
      fi
    done
    statement="$(jq -nc --arg hex "${digest_hex}" '{
      "_type": "https://in-toto.io/Statement/v0.1",
      "predicateType": "https://slsa.dev/provenance/v1",
      "subject": [{"name": "test", "digest": {"sha256": $hex}}],
      "predicate": {
        "buildDefinition": {
          "buildType": "https://tekton.dev/chains/v2/slsa",
          "externalParameters": {
            "runSpec": {
              "pipelineRef": {"name": "promote-npm"},
              "params": []
            }
          },
          "internalParameters": {},
          "resolvedDependencies": [{
            "uri": "git+https://github.com/calungaproject/index.git",
            "digest": {"sha1": "abc123def456"}
          }]
        },
        "runDetails": {
          "builder": {"id": "https://konflux-ci.dev/chains/v2"},
          "metadata": {
            "invocationId": "calunga-tenant/build-run-mock",
            "startedOn": "2026-02-19T21:40:00Z",
            "finishedOn": "2026-02-19T21:51:09Z"
          }
        }
      }
    }')"
    payload="$(printf '%s' "${statement}" | base64 -w0 2>/dev/null \
      || printf '%s' "${statement}" | base64)"
    jq -nc --arg payload "${payload}" '{
      payloadType: "application/vnd.in-toto+json",
      payload: $payload,
      signatures: [{keyid: "", sig: "mock-signature"}]
    }'
    return 0
  fi

  return 0
}

# Export mocks so plumbing-utils bash scripts (subprocesses) see them.
export -f select-oci-auth retry _copy_fixture oras cosign
