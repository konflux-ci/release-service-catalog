#!/usr/bin/env bash
#
# Summary:
#   Shared helper functions for GitHub API operations with retry logic
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/github-api-helpers.sh"
#   or
#   source "${SCRIPT_DIR}/lib/github-api-helpers.sh"
#
# Functions:
#   github_api_call_with_retry - Retry GitHub API calls with exponential backoff

# Retry helper for GitHub API calls with exponential backoff
# Usage: github_api_call_with_retry "description" curl_command [args...]
#
# This function wraps GitHub API calls to handle transient failures:
# - HTTP errors (4xx, 5xx status codes)
# - Network errors (timeouts, connection failures)
# - Rate limiting (HTTP 429 or rate limit messages)
# - Temporary GitHub API unavailability
#
# Features:
# - Automatically adds --fail-with-body to curl commands (fails on HTTP errors, preserves body)
# - 5 retry attempts with exponential backoff (2s, 4s, 8s, 16s, 32s)
# - All log messages go to stderr to keep stdout clean for JSON parsing
# - Returns the API response JSON on stdout (for command substitution)
# - Returns 0 on success, 1 on failure after all retries
#
# Example:
#   RESPONSE=$(github_api_call_with_retry "check repo" curl -s -H "Authorization: token $TOKEN" https://api.github.com/repos/owner/repo)
#   REPO_NAME=$(echo "$RESPONSE" | jq -r '.full_name // ""')
github_api_call_with_retry() {
  local description="$1"
  shift
  local max_attempts=5
  local attempt=1
  local delay=2
  local response=""
  
  # Inject --fail-with-body for curl commands to make them fail on HTTP errors (4xx, 5xx)
  # This ensures the exit code reflects actual HTTP failures, not just network issues
  local cmd=("$@")
  if [ "${cmd[0]}" = "curl" ]; then
    # Check if --fail or --fail-with-body is already present
    local has_fail=false
    for arg in "${cmd[@]}"; do
      if [[ "$arg" =~ ^--(fail|fail-with-body)$ ]] || [[ "$arg" =~ ^-[a-zA-Z]*f[a-zA-Z]*$ ]]; then
        has_fail=true
        break
      fi
    done
    
    # Add --fail-with-body if not already present (preserves error body for debugging)
    if [ "$has_fail" = false ]; then
      cmd=("${cmd[0]}" "--fail-with-body" "${cmd[@]:1}")
    fi
  fi
  
  while [ $attempt -le $max_attempts ]; do
    response=$("${cmd[@]}" 2>&1)
    local exit_code=$?
    
    # Check if curl succeeded (exit code 0 means both network success AND HTTP 2xx/3xx status)
    # Thanks to --fail-with-body, curl now fails (non-zero exit) on HTTP 4xx/5xx errors
    if [ $exit_code -eq 0 ]; then
      # Check for rate limiting
      local rate_limit_msg=$(echo "$response" | jq -r '.message // ""' 2>/dev/null | grep -i "rate limit" || true)
      if [ -n "$rate_limit_msg" ]; then
        echo "⚠️  GitHub API rate limit hit on attempt $attempt/$max_attempts for $description" >&2
      else
        # Success - output JSON response to stdout
        echo "$response"
        return 0
      fi
    else
      # Non-zero exit means either HTTP error (4xx/5xx) or network failure
      echo "⚠️  Request failed on attempt $attempt/$max_attempts for $description (exit code: $exit_code)" >&2
      if [ -n "$response" ]; then
        # If there's a response body, it might have error details
        local error_msg=$(echo "$response" | jq -r '.message // empty' 2>/dev/null || true)
        if [ -n "$error_msg" ]; then
          echo "   Error: $error_msg" >&2
        fi
      fi
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      echo "   Retrying in ${delay}s..." >&2
      sleep $delay
      delay=$((delay * 2))  # Exponential backoff
    fi
    attempt=$((attempt + 1))
  done
  
  echo "🔴 Failed after $max_attempts attempts for $description" >&2
  return 1
}
