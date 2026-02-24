#!/usr/bin/env bash
set -euo pipefail

# mocks to be injected into task step scripts
#
# Pyxis query strategy (confirmed against real Pyxis stage API, March 2026):
# - The image IS in Pyxis — found via image_id (the manifest digest stored by create-pyxis-image).
# - Query field: image_id == sha256:...  (NOT docker_image_digest — that field does not exist)
# - Completeness signal: rpm_manifest.rpms must be non-empty (populated by push-rpm-data-to-pyxis)
# - URL-encoded filter: image_id%3D%3Dsha256%3A...

function select-oci-auth() {
  # Return empty auth config (all registries are accessible in tests)
  echo '{}'
  return 0
}

function curl() {
  # Mock curl for testing
  local output_file=""
  local url=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -o)
        output_file="$2"
        shift 2
        ;;
      -w|--retry|--connect-timeout|--max-time)
        shift 2
        ;;
      --config|--cert|--key|--cacert)
        shift 2
        ;;
      -sS|--retry-all-errors|-s|-S)
        shift 1
        ;;
      *)
        # Last non-flag argument is the URL
        if [[ ! "$1" =~ ^- ]]; then
          url="$1"
        fi
        shift 1
        ;;
    esac
  done

  local json_response="[]"
  # Pyxis API: query by image_id (the manifest digest).
  # Completeness requires: non-empty rpm_manifest.rpms (populated by push-rpm-data-to-pyxis).
  # repositories[].tags is NOT required: unreliable in staging, redundant given rpm_manifest.rpms.
  case "$url" in
    *"pyxis.api.redhat.com/v1/images?filter=image_id%3D%3Dsha256%3Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"*)
      # Full release: rpm_manifest.rpms non-empty (tags also present but not required) → filtered out
      json_response='{"data":[{"image_id":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","rpm_manifest":{"rpms":[{"name":"bash"}]},"repositories":[{"tags":[{"name":"latest"},{"name":"v1"}]}]}]}'
      ;;
    *"pyxis.api.redhat.com/v1/images?filter=image_id%3D%3Dsha256%3Ab"*)
      # Partial: image found but rpm_manifest.rpms empty → push-rpm-data-to-pyxis incomplete → keep
      json_response='{"data":[{"image_id":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","rpm_manifest":{"rpms":[]},"repositories":[{"tags":[{"name":"latest"}]}]}]}'
      ;;
    *"pyxis.api.redhat.com/v1/images?filter=image_id%3D%3Dsha256%3Ac"*)
      # Partial: image found but no rpm_manifest at all → push-rpm-data-to-pyxis never ran → keep
      json_response='{"data":[{"image_id":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","repositories":[{"tags":[{"name":"latest"}]}]}]}'
      ;;
    *"pyxis.api.redhat.com/v1/images?filter=image_id%3D%3Dsha256%3Ad"*)
      # Staging scenario: rpm_manifest.rpms non-empty but repositories[].tags empty.
      # Must be FILTERED (rpm_manifest.rpms alone is sufficient).
      json_response='{"data":[{"image_id":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","rpm_manifest":{"rpms":[{"name":"glibc"}]},"repositories":[{"tags":[]}]}]}'
      ;;
    *"pyxis.api.redhat.com/v1/images?filter=image_id%3D%3D"*)
      json_response='{"data":[]}'
      ;;
  esac

  if [ -n "$output_file" ]; then
    echo "$json_response" > "$output_file"
  else
    echo "$json_response"
  fi

  printf "%s" "200"
}

function curl-with-retry() {
  curl "$@"
}

function oras() {
  if [[ "$1" != "resolve" ]]; then
    echo "Error: only 'oras resolve' is mocked" >&2
    return 1
  fi
  
  # Extract image reference (last argument)
  local image_ref="${*: -1}"
  
  case "$image_ref" in
    *"@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
      echo "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      return 0
      ;;
    *"@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
      echo "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      return 0
      ;;
    *"@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"*)
      echo "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      return 0
      ;;
    *)
      # Default: return the digest from the reference
      if [[ "$image_ref" =~ @(sha256:[a-f0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
      fi
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
  esac
}

function internal-request() {
  # Mock internal-request for fileUpdates completion checks.
  # The task parses the IR name from this output using awk '/created/ { print $2 }'.
  echo "internalrequests.appstudio.redhat.com 'mock-ir' created"
  return 0
}

function kubectl() {
  # Mock the InternalRequest lookup used by the filter task.
  #
  # Expected shape (name-based, requires only 'get' RBAC):
  # kubectl get internalrequest <name> -o json
  if [ "${1:-}" = "get" ] && [ "${2:-}" = "internalrequest" ]; then
    local complete="true"
    if [ -n "${DATA_FILE:-}" ] && [ -f "${DATA_FILE}" ]; then
      complete="$(
        jq -r 'if has("mock_file_updates_complete") then .mock_file_updates_complete else true end' \
          "${DATA_FILE}" 2>/dev/null || echo "true"
      )"
    fi

    jq -nc --arg complete "${complete}" '
      {
        status: {
          results: {
            result: "Success",
            file_updates_complete: ($complete == "true")
          }
        }
      }
    '
    return 0
  fi

  echo "Error: unexpected kubectl call: $*" >&2
  return 1
}
