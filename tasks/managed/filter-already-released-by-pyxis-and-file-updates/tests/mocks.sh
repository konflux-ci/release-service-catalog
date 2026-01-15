#!/usr/bin/env bash
set -euo pipefail

# mocks to be injected into task step scripts

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
  case "$url" in
    *"pyxis.api.redhat.com/v1/images?filter=docker_image_digest%3D%3Dsha256%3Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"*)
      json_response='{"data":[{"repositories":[{"tags":["latest","v1"],"content_sets":["rhel-9-for-x86_64-appstream-rpms"]}]}]}'
      ;;
    *"pyxis.api.redhat.com/v1/images?filter=docker_image_digest%3D%3D"*)
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
  # The task retrieves the InternalRequest object via kubectl labels, so this only
  # needs to return success.
  echo "internalrequests.appstudio.redhat.com 'mock-ir' created"
  return 0
}

function kubectl() {
  # Mock only the InternalRequest lookup used by the filter task.
  #
  # Expected shape:
  # kubectl get internalrequest -l ... -o jsonpath='{.items[0]}' --sort-by=...
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
