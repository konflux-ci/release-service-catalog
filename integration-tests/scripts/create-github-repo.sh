#!/usr/bin/env bash
#
# Summary:
#   Creates a new GitHub repository using the GitHub REST API.
#   Can create repositories in user account or organizations.
#
# Parameters:
#   $1: repo_name         - The name of the repository to create (just the name, not owner/name)
#                          OR full name like "org/repo" to create in an organization.
#
# Environment Variables:
#   GITHUB_TOKEN        - A GitHub personal access token with repo creation permissions. Required.
#
# Dependencies:
#   curl, jq

set -eo pipefail

# Enable debug mode if DEBUG environment variable is set
if [ -n "${DEBUG}" ]; then
  set -x
fi

# Source shared GitHub API helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/github-api-helpers.sh"

if [ -z $GITHUB_TOKEN ] ; then
  echo "🔴 error: missing env var GITHUB_TOKEN"
  exit 1
fi

repo_name=$1
if [ -z "$repo_name" ] ; then
  echo "🔴 error: missing parameter repo_name"
  echo "Usage: $0 <repo_name>"
  echo "Example: $0 my-new-repo"
  echo "Example: $0 myorg/my-new-repo"
  exit 1
fi

# Check if repo_name contains organization (has a slash)
if [[ "$repo_name" == *"/"* ]]; then
  # Organization repository format: org/repo
  ORG_NAME=$(dirname "$repo_name")
  ACTUAL_REPO_NAME=$(basename "$repo_name")
  full_repo_name="$repo_name"
  CREATE_URL="https://api.github.com/orgs/${ORG_NAME}/repos"
  
else
  # User repository format: just repo name
  # Get current user to construct full repo name
  echo "Getting GitHub user information..."
  USER_RESPONSE=$(github_api_call_with_retry "get user info" curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)
  GITHUB_USER=$(echo "${USER_RESPONSE}" | jq -r '.login // ""')
  if [ -z "${GITHUB_USER}" ]; then
    echo "🔴 error: could not get GitHub user information"
    echo "   Check that GITHUB_TOKEN is valid and has appropriate permissions"
    exit 1
  fi
  
  ORG_NAME="$GITHUB_USER"
  ACTUAL_REPO_NAME="$repo_name"
  full_repo_name="${GITHUB_USER}/${repo_name}"
  CREATE_URL="https://api.github.com/user/repos"
  
fi

# Check if repository already exists
echo "Checking if repository ${full_repo_name} already exists..."
# Use simple curl for existence check; 404 is expected if repo doesn't exist yet
EXISTING_REPO_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${full_repo_name} 2> /dev/null)
EXISTING_REPO=$(jq -r '.full_name // ""' <<< "${EXISTING_REPO_RESPONSE}")
if [ -n "${EXISTING_REPO}" ]; then
  echo "⚠️  Repository ${full_repo_name} already exists"
  echo "   URL: https://github.com/${full_repo_name}"
  exit 0
fi

# Create the repository
echo "Creating repository ${full_repo_name}..."

CREATE_RESPONSE=$(github_api_call_with_retry "create repo" curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -d "{\"name\":\"${ACTUAL_REPO_NAME}\"}" \
  "${CREATE_URL}")

# Check if creation was successful
CREATED_REPO=$(echo "$CREATE_RESPONSE" | jq -r '.full_name // ""')
if [ -z "${CREATED_REPO}" ]; then
  echo "🔴 error: failed to create repository ${full_repo_name}"
  echo "Response: $CREATE_RESPONSE"
  
  # Check for common error messages
  ERROR_MSG=$(echo "$CREATE_RESPONSE" | jq -r '.message // ""')
  if [ -n "${ERROR_MSG}" ]; then
    echo "Error message: ${ERROR_MSG}"
  fi
  
  exit 1
fi

# Verify the repository was created successfully
# Give GitHub a moment to propagate the new repository
echo "Verifying repository creation..."
sleep 2
VERIFY_REPO=$(github_api_call_with_retry "verify repo creation" curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${full_repo_name} | jq -r '.full_name // ""')
if [ "${VERIFY_REPO}" = "${full_repo_name}" ]; then
  echo "✅ Repository ${full_repo_name} created successfully!"
  echo "   - URL: https://github.com/${full_repo_name}"
  echo "   - Clone URL: https://github.com/${full_repo_name}.git"
  echo "   - SSH URL: git@github.com:${full_repo_name}.git"
else
  echo "🔴 error: repository creation verification failed"
  exit 1
fi
