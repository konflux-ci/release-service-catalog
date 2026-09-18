#!/bin/bash

# Script to find open PRs where a file was modified and check if they contain a specific string
# Usage: ./find-pr-with-sha-and-file.sh <org/repo> <search-string> <file-path>

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <org/repo> <search-string> <file-path>"
    echo ""
    echo "Find open PRs where a file was modified and check if the file contains a specific string"
    echo ""
    echo "Examples:"
    echo "  $0 microsoft/vscode 'console.log' src/main.ts"
    echo "  $0 kubernetes/kubernetes 'TODO:' pkg/controller/deployment.go"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_TOKEN - GitHub token for authentication (recommended to avoid rate limits)"
    echo "  MAX_PRS      - Maximum number of PRs to check (default: 20)"
    exit 1
}

log_info() {
    echo -e "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ -n "${DEBUG:-}" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}

github_api_request() {
    local url="$1"
    local curl_cmd="curl -s"

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_cmd="$curl_cmd -H 'Authorization: token $GITHUB_TOKEN'"
    fi

    curl_cmd="$curl_cmd -H 'Accept: application/vnd.github.v3+json'"

    local response
    response=$(eval "$curl_cmd -w '%{http_code}' '$url'")

    local http_status="${response: -3}"
    local response_body="${response%???}"

    if [ "$http_status" -eq 200 ]; then
        echo "$response_body"
        return 0
    else
        log_error "API request failed with status $http_status"
        log_error "URL: $url"
        if [ "$http_status" -eq 404 ]; then
            log_error "Repository not found or not accessible"
        elif [ "$http_status" -eq 403 ]; then
            log_error "Access forbidden - check GitHub token permissions or rate limits"
        fi
        log_error "Response: $response_body"
        return 1
    fi
}

check_file_modified_in_pr() {
    local repo_path="$1"
    local pr_number="$2"
    local target_file="$3"

    log_debug "Checking if file '$target_file' was modified in PR #$pr_number"

    local files_url="https://api.github.com/repos/$repo_path/pulls/$pr_number/files?per_page=100"
    local files_response
    files_response=$(github_api_request "$files_url") || return 1

    local modified_files
    modified_files=$(jq -r '.[].filename' <<< "$files_response")

    if grep -q "^${target_file}$" <<< "$modified_files"; then
        log_debug "File '$target_file' was modified in PR #$pr_number"
        return 0
    else
        log_debug "File '$target_file' was not modified in PR #$pr_number"
        return 1
    fi
}

check_string_in_file() {
    local repo_path="$1"
    local pr_number="$2"
    local target_file="$3"
    local search_string="$4"
    local head_sha="$5"

    log_debug "Checking if string '$search_string' exists in file '$target_file' in PR #$pr_number (SHA: $head_sha)"

    local file_url="https://api.github.com/repos/$repo_path/contents/$target_file?ref=$head_sha"
    local file_response
    file_response=$(github_api_request "$file_url") || return 1

    local base64_content
    base64_content=$(jq -r '.content // empty' <<< "$file_response" | tr -d '\n')

    if [ -z "$base64_content" ]; then
        log_debug "Could not extract content from file response"
        return 1
    fi

    log_debug "Extracted base64 content length: ${#base64_content}"

    local file_content
    file_content=$(echo "$base64_content" | base64 -d 2>/dev/null) || true

    if [ -z "$file_content" ]; then
        log_debug "Base64 decode returned empty content"
        if command -v openssl >/dev/null 2>&1; then
            file_content=$(echo "$base64_content" | openssl base64 -d 2>/dev/null) || true
        fi
        if [ -z "$file_content" ]; then
            log_debug "All base64 decoding attempts returned empty content"
            return 1
        fi
    fi

    if grep -q -F "$search_string" <<< "$file_content"; then
        log_debug "String '$search_string' found in file '$target_file' in PR #$pr_number"
        return 0
    else
        log_debug "String '$search_string' not found in file '$target_file' in PR #$pr_number"
        return 1
    fi
}

get_pr_details() {
    local repo_path="$1"
    local pr_number="$2"
    local cached_pr_list="$3"

    jq -r --argjson n "$pr_number" --arg url "https://github.com/$repo_path/pull/$pr_number" '
        .[] | select(.number == $n) |
        "  Title: \(.title)\n  State: \(.state)\n  Author: \(.user.login)\n  Created: \(.created_at)\n  URL: \($url)"
    ' <<< "$cached_pr_list"
}

if [ $# -ne 3 ]; then
    log_error "Invalid number of arguments"
    usage
fi

REPO_PATH="$1"
SEARCH_STRING="$2"
FILE_PATH="$3"
MAX_PRS="${MAX_PRS:-20}"

if [[ ! "$REPO_PATH" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    log_error "Invalid repository path format. Expected format: org/repo"
    exit 1
fi

if [ -z "$SEARCH_STRING" ]; then
    log_error "Search string cannot be empty"
    exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warn "GITHUB_TOKEN not set. API requests may be rate limited"
fi

log_info "Searching for open PRs in '$REPO_PATH' that modified '$FILE_PATH'"
log_info "Looking for string: $SEARCH_STRING"
log_info "Maximum PRs to check: $MAX_PRS"

PR_LIST_URL="https://api.github.com/repos/$REPO_PATH/pulls?state=open&sort=updated&direction=desc&per_page=100"

log_debug "PR list URL: $PR_LIST_URL"

PR_LIST_RESPONSE=$(github_api_request "$PR_LIST_URL") || {
    log_error "Failed to list open PRs"
    exit 1
}

log_debug "PR list response received"

PR_NUMBERS=$(jq -r '.[].number' <<< "$PR_LIST_RESPONSE" | head -n "$MAX_PRS")

if [ -z "$PR_NUMBERS" ]; then
    log_warn "No open PRs found in repository '$REPO_PATH'"
    log_info "Search was performed for:"
    log_info "  Repository: $REPO_PATH"
    exit 0
fi

TOTAL_OPEN=$(jq -r 'length' <<< "$PR_LIST_RESPONSE")
PR_COUNT=$(echo "$PR_NUMBERS" | wc -l)
log_info "Found $TOTAL_OPEN open PRs in repository, checking up to $PR_COUNT..."
echo ""

RELEVANT_PRS=()
FOUND_PRS=()
CHECKED_COUNT=0

for pr_number in $PR_NUMBERS; do
    CHECKED_COUNT=$((CHECKED_COUNT + 1))

    echo "Checking PR #$pr_number ($CHECKED_COUNT/$PR_COUNT) for file modifications..."

    if check_file_modified_in_pr "$REPO_PATH" "$pr_number" "$FILE_PATH"; then
        echo "  ✓ File '$FILE_PATH' was modified in PR #$pr_number"
        RELEVANT_PRS+=("$pr_number")

        head_sha=$(jq -r --argjson n "$pr_number" '.[] | select(.number == $n) | .head.sha' <<< "$PR_LIST_RESPONSE")

        if check_string_in_file "$REPO_PATH" "$pr_number" "$FILE_PATH" "$SEARCH_STRING" "$head_sha"; then
            log_info "  ✅ Found string '$SEARCH_STRING' in file '$FILE_PATH' in PR #$pr_number"
            FOUND_PRS+=("$pr_number")

            get_pr_details "$REPO_PATH" "$pr_number" "$PR_LIST_RESPONSE"
            echo ""
        else
            echo "  ❌ String not found in file '$FILE_PATH' in PR #$pr_number"
        fi
    else
        echo "  ⏭️  File '$FILE_PATH' not modified in PR #$pr_number"
    fi
done

echo "Summary:"
echo "========="
echo "Open PRs checked: $CHECKED_COUNT"
echo "PRs that modified '$FILE_PATH': ${#RELEVANT_PRS[@]}"
echo "PRs containing string: ${#FOUND_PRS[@]}"

if [ ${#RELEVANT_PRS[@]} -eq 0 ]; then
    log_warn "No open PRs found that modified the file '$FILE_PATH'"
    exit 0
elif [ ${#FOUND_PRS[@]} -gt 0 ]; then
    echo ""
    log_info "PRs containing string '$SEARCH_STRING':"
    for pr in "${FOUND_PRS[@]}"; do
        echo "  - PR #$pr: https://github.com/$REPO_PATH/pull/$pr"
    done
    exit 0
else
    log_warn "String '$SEARCH_STRING' was not found in file '$FILE_PATH' in any open PR"
    exit 1
fi
