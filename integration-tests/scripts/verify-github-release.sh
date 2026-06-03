#!/bin/bash

# Script to verify if a GitHub release tag exists in a repository
# Usage: ./verify-github-release.sh <org/repo> <release-tag>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo "Usage: $0 <org/repo> <release-tag>"
    echo ""
    echo "Examples:"
    echo "  $0 microsoft/vscode v1.85.0"
    echo "  $0 kubernetes/kubernetes v1.28.0"
    echo ""
    echo "Environment variables:"
    echo "  GH_TOKEN - GitHub token for authentication (optional, helps avoid rate limits)"
    exit 1
}

# Function to log messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    log_error "Invalid number of arguments"
    usage
fi

REPO_PATH="$1"
RELEASE_TAG="$2"

# Validate repository path format
if [[ ! "$REPO_PATH" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    log_error "Invalid repository path format. Expected format: org/repo"
    exit 1
fi

# Extract org and repo from the path
IFS='/' read -r ORG REPO <<< "$REPO_PATH"

log_info "Checking release tag '$RELEASE_TAG' in repository '$REPO_PATH'"

# Prepare curl command with optional authentication
CURL_CMD="curl -s"
if [ -n "${GH_TOKEN:-}" ]; then
    CURL_CMD="$CURL_CMD -H 'Authorization: token $GH_TOKEN'"
    log_info "Using GitHub token for authentication"
fi

# GitHub API URL for the specific release
API_URL="https://api.github.com/repos/$REPO_PATH/releases/tags/$RELEASE_TAG"

# Make the API request and capture both response and HTTP status
RESPONSE=$(eval "$CURL_CMD -w '%{http_code}' '$API_URL'")

# Extract HTTP status code (last 3 characters)
HTTP_STATUS="${RESPONSE: -3}"
# Extract response body (everything except last 3 characters)
RESPONSE_BODY="${RESPONSE%???}"

case "$HTTP_STATUS" in
    200)
        log_info "✅ Release tag '$RELEASE_TAG' exists in repository '$REPO_PATH'"
        ;;
    404)
        log_error "❌ Release tag '$RELEASE_TAG' does not exist in repository '$REPO_PATH'"
        
        # Suggest checking available releases
        echo ""
        log_info "To see available releases, visit: https://github.com/$REPO_PATH/releases"
        log_info "Or use the API: https://api.github.com/repos/$REPO_PATH/releases"
        
        exit 1
        ;;
    403)
        log_error "❌ Access forbidden. Possible causes:"
        echo "  - Repository is private and requires authentication"
        echo "  - API rate limit exceeded"
        echo "  - Invalid GitHub token"
        
        if [ -z "${GITHUB_TOKEN:-}" ]; then
            log_warn "Consider setting GITHUB_TOKEN environment variable to avoid rate limits"
        fi
        
        exit 1
        ;;
    401)
        log_error "❌ Unauthorized. GitHub token may be invalid"
        exit 1
        ;;
    *)
        log_error "❌ Unexpected HTTP status: $HTTP_STATUS"
        log_error "Response: $RESPONSE_BODY"
        exit 1
        ;;
esac

FAIL_CHECK=0
if ! jq -e 'any(.assets[]?; .name | test(".*SHA256SUMS$"))' <<< "$RESPONSE_BODY" >/dev/null; then
    log_error "❌ Missing asset 'SHA256SUMS' in release"
    FAIL_CHECK=1
fi

if ! jq -e '[ .assets[]? | select(.name | endswith(".sig")) ] | length == 1' <<< "$RESPONSE_BODY" >/dev/null; then
    log_error "❌ Expected exactly one '.sig' asset in release"
    FAIL_CHECK=1
fi

if ! jq -e '[ .assets[]? | select(.name | endswith(".zip")) ] | length == 1' <<< "$RESPONSE_BODY" >/dev/null; then
    log_error "❌ Expected exactly one '.zip' asset in release"
    FAIL_CHECK=1
fi

if [ "$FAIL_CHECK" -eq 1 ]; then
    log_info "Available assets:"
    jq -r '.assets[]?.name' <<< "$RESPONSE_BODY"
    exit 1
fi

log_info "✅ All requested assets ('SHA256SUMS', '.sig', and '.zip') are present in the release."
exit 0
