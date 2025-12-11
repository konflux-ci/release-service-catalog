#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch curl-with-retry from release-service-utils if not already cached
CURL_WITH_RETRY="${SCRIPT_DIR}/.curl-with-retry"
if [ ! -f "$CURL_WITH_RETRY" ]; then
    echo "Fetching curl-with-retry from release-service-utils..." >&2
    curl -sSL -o "$CURL_WITH_RETRY" \
        "https://raw.githubusercontent.com/konflux-ci/release-service-utils/main/utils/curl-with-retry"
    chmod +x "$CURL_WITH_RETRY"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
log_info() { echo -e "$1"; }

show_usage() {
    cat << EOF
Usage: $0 <org/repo> <old-file-path> <new-file-path> [options]
Options: -h|--help -b|--branch BRANCH -m|--message MSG --token TOKEN
Environment: GH_TOKEN (GitHub token)
EOF
}

validate_repo_format() {
    [[ "$1" == *"/"* ]] && [[ -n "${1%/*}" ]] && [[ -n "${1#*/}" ]] || { log_error "Invalid repo format: $1"; return 1; }
}

check_file_exists() {
    local response=$(curl -s -H "Authorization: token $4" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$1/contents/$3?ref=$2" 2>/dev/null || echo "")
    [[ -n "$response" ]] && echo "$response" | jq -e '.sha' >/dev/null 2>&1
}

get_file_info() {
    local response=$(curl -s -H "Authorization: token $4" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$1/contents/$3?ref=$2" 2>/dev/null)
    [[ -n "$response" ]] || { log_error "Failed to get file info: $3"; return 1; }
    echo "$response" | jq -e '.message' >/dev/null 2>&1 && { log_error "API error: $(echo "$response" | jq -r '.message')"; return 1; }
    echo "$response"
}

create_file() {
    local payload=$(jq -n --arg message "$6" --arg content "$4" --arg encoding "$5" --arg branch "$2" \
        '{message: $message, content: $content, encoding: $encoding, branch: $branch}')
    local response=$(curl -s -w "\n%{http_code}" -X PUT -H "Authorization: token $7" \
        -H "Accept: application/vnd.github.v3+json" -H "Content-Type: application/json" \
        -d "$payload" "https://api.github.com/repos/$1/contents/$3")
    local code=$(echo "$response" | tail -n1)
    [[ "$code" == "201" ]] && { log_success "Created: $3"; return 0; }
    log_error "Create failed: $3 (HTTP $code)"
    echo "$response" | head -n -1 | jq -r '.message // empty' 2>/dev/null
    return 1
}

delete_file() {
    local payload=$(jq -n --arg message "$5" --arg sha "$4" --arg branch "$2" \
        '{message: $message, sha: $sha, branch: $branch}')
    local response=$(curl -s -w "\n%{http_code}" -X DELETE -H "Authorization: token $6" \
        -H "Accept: application/vnd.github.v3+json" -H "Content-Type: application/json" \
        -d "$payload" "https://api.github.com/repos/$1/contents/$3")
    local code=$(echo "$response" | tail -n1)
    [[ "$code" == "200" ]] && { log_success "Deleted: $3"; return 0; }
    log_error "Delete failed: $3 (HTTP $code)"
    echo "$response" | head -n -1 | jq -r '.message // empty' 2>/dev/null
    return 1
}

check_branch_exists() {
    local repo="$1" branch="$2" token="$3"
    local response=$("$CURL_WITH_RETRY" --retry 3 --retry-all-errors -s \
        -H "Authorization: token $token" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$repo/branches/$branch" 2>/dev/null || echo "")
    [[ -n "$response" ]] && echo "$response" | jq -e '.name' >/dev/null 2>&1
}

rename_file() {
    local repo="$1" old_path="$2" new_path="$3" branch="$4" commit_message="$5" token="$6"
    
    log_info "Repository: $repo\nBranch: $branch\nOld: $old_path\nNew: $new_path\n---"
    
    check_branch_exists "$repo" "$branch" "$token" || { log_error "Branch '$branch' not found"; return 1; }
    check_file_exists "$repo" "$branch" "$old_path" "$token" || { log_error "File '$old_path' not found"; return 1; }
    check_file_exists "$repo" "$branch" "$new_path" "$token" && { log_error "File '$new_path' already exists"; return 1; }
    
    local file_info=$(get_file_info "$repo" "$branch" "$old_path" "$token") || return 1
    local file_sha=$(echo "$file_info" | jq -r '.sha')
    local file_content=$(echo "$file_info" | jq -r '.content')
    local file_encoding=$(echo "$file_info" | jq -r '.encoding // "base64"')
    
    [[ -z "$file_sha" || "$file_sha" == "null" ]] && { log_error "Could not get SHA for: $old_path"; return 1; }
    
    local msg="${commit_message:-"Rename $old_path to $new_path"}"
    create_file "$repo" "$branch" "$new_path" "$file_content" "$file_encoding" "$msg" "$token" || return 1
    delete_file "$repo" "$branch" "$old_path" "$file_sha" "$msg" "$token" || {
        log_warning "New file created but old file still exists"
        return 1
    }
}

main() {
    local repo="" old_path="" new_path="" branch="main" commit_message="" token=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage; exit 0 ;;
            -b|--branch) branch="$2"; shift 2 ;;
            --branch=*) branch="${1#*=}"; shift ;;
            -m|--message) commit_message="$2"; shift 2 ;;
            --message=*) commit_message="${1#*=}"; shift ;;
            --token) token="$2"; shift 2 ;;
            --token=*) token="${1#*=}"; shift ;;
            -*) log_error "Unknown option: $1"; show_usage; exit 1 ;;
            *) 
                if [[ -z "$repo" ]]; then repo="$1"
                elif [[ -z "$old_path" ]]; then old_path="$1"
                elif [[ -z "$new_path" ]]; then new_path="$1"
                else log_error "Too many arguments"; exit 1; fi
                shift ;;
        esac
    done
    
    [[ -z "$repo" || -z "$old_path" || -z "$new_path" ]] && { log_error "Missing arguments"; show_usage; exit 1; }
    [[ "$old_path" == "$new_path" ]] && { log_error "Paths are the same"; exit 1; }
    
    token="${token:-$GH_TOKEN}"
    [[ -z "$token" ]] && { log_error "GitHub token required (GH_TOKEN or --token)"; exit 1; }
    
    validate_repo_format "$repo" || exit 1
    command -v curl >/dev/null && command -v jq >/dev/null || { log_error "curl and jq required"; exit 1; }
    
    if rename_file "$repo" "$old_path" "$new_path" "$branch" "$commit_message" "$token"; then
        log_success "Renamed '$old_path' to '$new_path'"
    else
        log_error "Rename failed"; exit 1
    fi
}

main "$@"
