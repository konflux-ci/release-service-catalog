#!/usr/bin/env bash
#
# Summary:
#   Deletes a GitHub repository using the GitHub REST API.
#   ⚠️  WARNING: This is a destructive operation that cannot be undone!
#
# Parameters:
#   $1: repo_name - The name of the GitHub repository (e.g., "owner/repo").
#
# Environment Variables:
#   GITHUB_TOKEN - A GitHub personal access token with permissions to delete
#                  repositories. Required. Must have 'delete_repo' scope.
#
# Dependencies:
#   curl, jq

set -eo pipefail

if [ -z $GITHUB_TOKEN ] ; then
  echo "🔴 error: missing env var GITHUB_TOKEN"
  exit 1
fi

repo_name=$1
if [ -z "$repo_name" ] ; then
  echo "🔴 error: missing parameter repo_name"
  echo "Usage: $0 <repo_name>"
  echo "Example: $0 myorg/my-repository"
  exit 1
fi

# Verify repository exists before attempting deletion
echo "Verifying repository ${repo_name} exists..."
REPO_RESPONSE=$(curl -L \
  --silent \
  --max-time 30 \
  --connect-timeout 10 \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/${repo_name} 2>&1)

if [ $? -ne 0 ]; then
  echo "🔴 error: Failed to verify repository ${repo_name}"
  echo "   Check network connectivity and GITHUB_TOKEN validity"
  echo "   Curl response: ${REPO_RESPONSE}"
  exit 1
fi

REPO_CHECK=$(echo "${REPO_RESPONSE}" | jq -r '.full_name // ""' 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "🔴 error: Failed to parse GitHub API response as JSON"
  echo "   Raw response: ${REPO_RESPONSE}"
  echo "   This might be an HTML error page or invalid response"
  exit 1
fi

if [ -z "${REPO_CHECK}" ]; then
  echo "⚠️ warning: repository ${repo_name} not found or not accessible"
  echo "   Check that:"
  echo "   1. Repository name is correct"
  echo "   2. Repository exists"
  echo "   3. GITHUB_TOKEN has access to the repository"
  exit 0
fi

# Perform the deletion
echo "Deleting repository ${repo_name}..."
DELETE_RESPONSE=$(curl -L \
  --silent \
  --max-time 60 \
  --connect-timeout 10 \
  -X DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/${repo_name} \
  -w "%{http_code}" -o /dev/null -s)

if [ $? -ne 0 ]; then
  echo "🔴 error: Failed to delete repository ${repo_name}"
  echo "   Check network connectivity and GITHUB_TOKEN validity"
  exit 1
fi

# Check the HTTP response code
if [ "${DELETE_RESPONSE}" = "204" ]; then
  echo "🗑️  GH Repository ${repo_name} deleted successfully"
elif [ "${DELETE_RESPONSE}" = "403" ]; then
  echo "🔴 error: Permission denied (HTTP 403)"
  echo "   Your GITHUB_TOKEN may not have the 'delete_repo' scope"
  echo "   or you may not have admin access to this repository"
  exit 1
elif [ "${DELETE_RESPONSE}" = "404" ]; then
  echo "🔴 error: Repository not found (HTTP 404)"
  echo "   Repository may have already been deleted or name is incorrect"
  exit 1
else
  echo "🔴 error: Deletion failed with HTTP status ${DELETE_RESPONSE}"
  exit 1
fi
