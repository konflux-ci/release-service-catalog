#!/usr/bin/env bash
set -euo pipefail

# mocks to be injected into task step scripts

function curl() {
  # Mock curl for GitLab API query
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
      --config|--cacert)
        shift 2
        ;;
      -sS|--retry-all-errors|-s|-S)
        shift 1
        ;;
      *)
        if [[ ! "$1" =~ ^- ]]; then
          url="$1"
        fi
        shift 1
        ;;
    esac
  done

  # component_group is set by the task script before invoking curl
  local json_response="[]"
  case "${component_group:-}" in
    merged-app)
      json_response='[{"title":"[Konflux release] merged-app: fileUpdates changes abc","state":"merged","web_url":"https://gitlab.example.com/merged"}]'
      ;;
    open-app)
      json_response='[{"title":"[Konflux release] open-app: fileUpdates changes def","state":"opened","web_url":"https://gitlab.example.com/open"}]'
      ;;
    *)
      json_response='[]'
      ;;
  esac

  if [ -n "$output_file" ]; then
    echo "$json_response" > "$output_file"
  else
    echo "$json_response"
  fi

  # Simulate curl -w "%{http_code}"
  printf "%s" "200"
}
