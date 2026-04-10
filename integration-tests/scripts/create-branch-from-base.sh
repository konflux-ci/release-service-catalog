#!/usr/bin/env bash
#
# Summary:
#   Creates a new branch in a GitHub repository based on the latest commit of
#   an existing base branch.
#
# Parameters:
#   $1: repo_name         - The name of the GitHub repository (e.g., "owner/repo").
#   $2: base_branch_name  - The name of the existing branch from which to create
#                           the new branch.
#   $3: new_branch_name   - The name for the new branch to be created.
#
# Environment Variables:
#   GITHUB_TOKEN        - A GitHub personal access token with permissions to read
#                         refs and create branches in the repository. Required.
#
# Dependencies:
#   curl, jq

set -eo pipefail

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
  exit 1
fi
base_branch_name=$2
if [ -z "$base_branch_name" ] ; then
  echo "🔴 error: missing parameter base_branch_name"
  exit 1
fi
new_branch_name=$3
if [ -z "$new_branch_name" ] ; then
  echo "🔴 error: missing parameter new_branch_name"
  exit 1
fi

SHA=$(github_api_call_with_retry "get base branch SHA" curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${repo_name}/git/refs/heads/${base_branch_name} | jq -r '.object.sha // ""')
if [ -z "${SHA}" ]; then
  echo "🔴 error: could not get SHA for base branch $base_branch_name"
  exit 1
fi
echo "Current SHA for base branch $base_branch_name is  $SHA"

echo "Creating new branch called ${new_branch_name} based on branch $base_branch_name"
github_api_call_with_retry "create branch" curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
 -d  "{\"ref\": \"refs/heads/${new_branch_name}\",\"sha\": \"$SHA\"}"  https://api.github.com/repos/${repo_name}/git/refs > /dev/null

# Verify the branch exists and is pullable with retry logic
echo "Verifying that branch ${new_branch_name} exists and is pullable..."

max_attempts=5
attempt=1
verification_success=false

while [ $attempt -le $max_attempts ]; do
  echo "Verification attempt ${attempt}/${max_attempts}..."
  
  # Check if the branch exists by getting its ref
  NEW_BRANCH_SHA=$(github_api_call_with_retry "verify branch ref" curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${repo_name}/git/refs/heads/${new_branch_name} | jq -r '.object.sha // ""')
  
  if [ -n "${NEW_BRANCH_SHA}" ]; then
    # Verify the SHA matches what we expected
    if [ "${NEW_BRANCH_SHA}" = "${SHA}" ]; then
      # Test if the branch is pullable by attempting to get its info
      BRANCH_INFO=$(github_api_call_with_retry "verify branch pullable" curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${repo_name}/branches/${new_branch_name})
      BRANCH_EXISTS=$(echo "$BRANCH_INFO" | jq -r '.name // ""')
      
      if [ "${BRANCH_EXISTS}" = "${new_branch_name}" ]; then
        echo "✅ Branch ${new_branch_name} successfully created and is pullable"
        echo "   - SHA: ${NEW_BRANCH_SHA}"
        echo "   - Based on: ${base_branch_name}"
        echo "   - Verified on attempt: ${attempt}"
        verification_success=true
        break
      else
        echo "⚠️  Branch ${new_branch_name} exists but is not yet pullable (attempt ${attempt}/${max_attempts})"
      fi
    else
      echo "⚠️  Branch ${new_branch_name} SHA (${NEW_BRANCH_SHA}) does not match expected SHA (${SHA}) (attempt ${attempt}/${max_attempts})"
    fi
  else
    echo "⚠️  Branch ${new_branch_name} does not exist yet (attempt ${attempt}/${max_attempts})"
  fi
  
  # Wait before retrying (except on the last attempt)
  if [ $attempt -lt $max_attempts ]; then
    echo "Waiting 3 seconds before retry..."
    sleep 3
  fi
  
  attempt=$((attempt + 1))
done

# Check if verification ultimately succeeded
if [ "$verification_success" = false ]; then
  echo "🔴 error: branch ${new_branch_name} verification failed after ${max_attempts} attempts"
  echo "   - Branch may not have been created successfully"
  echo "   - Branch may not be pullable or accessible"
  exit 1
fi
