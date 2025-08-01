#!/usr/bin/env bash
#
# Summary:
#   Copies a branch from one GitHub repository to another repository using git commands.
#   This works even when repositories don't share commit history. If the destination
#   repository doesn't exist, it will be created automatically.
#
# Parameters:
#   $1: source_repo       - The name of the source GitHub repository (e.g., "owner/repo").
#   $2: source_branch     - The name of the branch to copy from the source repository.
#   $3: dest_repo         - The name of the destination GitHub repository (e.g., "owner/repo").
#   $4: dest_branch       - The name for the new branch in the destination repository.
#
# Environment Variables:
#   GITHUB_TOKEN        - A GitHub personal access token with repo creation and push permissions. Required.
#
# Dependencies:
#   git, curl, jq, create-github-repo.sh (must be in same directory)
#
# Note:
#   This script clones the source repo, adds the destination as a remote, and pushes
#   the branch directly. This works regardless of whether repos share history.
#   If the destination repository doesn't exist, it will be created automatically as a public repository.

set -eo pipefail

# Enable debug mode if DEBUG environment variable is set
if [ -n "${DEBUG}" ]; then
  set -x
  echo "🐛 Debug mode enabled"
fi

if [ -z $GITHUB_TOKEN ] ; then
  echo "🔴 error: missing env var GITHUB_TOKEN"
  exit 1
fi

source_repo=$1
if [ -z "$source_repo" ] ; then
  echo "🔴 error: missing parameter source_repo"
  exit 1
fi

source_branch=$2
if [ -z "$source_branch" ] ; then
  echo "🔴 error: missing parameter source_branch"
  exit 1
fi

dest_repo=$3
if [ -z "$dest_repo" ] ; then
  echo "🔴 error: missing parameter dest_repo"
  exit 1
fi

dest_branch=$4
if [ -z "$dest_branch" ] ; then
  echo "🔴 error: missing parameter dest_branch"
  exit 1
fi

# Verify source repository exists and is accessible
echo "Verifying source repository ${source_repo} exists and is accessible..."
SOURCE_REPO_RESPONSE=$(curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${source_repo} 2> /dev/null)
if [ -n "${DEBUG}" ]; then
  echo "🐛 Source repo API response: ${SOURCE_REPO_RESPONSE}"
fi
SOURCE_REPO_CHECK=$(echo "${SOURCE_REPO_RESPONSE}" | jq -r '.full_name // ""')
if [ -z "${SOURCE_REPO_CHECK}" ]; then
  echo "🔴 error: source repository ${source_repo} not found or not accessible"
  if [ -n "${DEBUG}" ]; then
    echo "🐛 Full API response: ${SOURCE_REPO_RESPONSE}"
  fi
  echo "   Check that:"
  echo "   1. Repository name is correct"
  echo "   2. Repository exists"
  echo "   3. GITHUB_TOKEN has access to read the repository"
  exit 1
fi

# Verify destination repository exists and is accessible
echo "Verifying destination repository ${dest_repo} exists and is accessible..."
DEST_REPO_RESPONSE=$(curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${dest_repo} 2> /dev/null)
if [ -n "${DEBUG}" ]; then
  echo "🐛 Destination repo API response: ${DEST_REPO_RESPONSE}"
fi
DEST_REPO_CHECK=$(echo "${DEST_REPO_RESPONSE}" | jq -r '.full_name // ""')
if [ -z "${DEST_REPO_CHECK}" ]; then
  echo "⚠️  Destination repository ${dest_repo} not found"
  echo "   Attempting to create it automatically..."
  
  # Pass the full repository path to the create script (it now handles org/repo format)
  if [ -n "${DEBUG}" ]; then
    echo "🐛 Full dest_repo: ${dest_repo}"
  fi
  
  # Get the directory where this script is located to find the helper script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${SCRIPT_DIR}/create-github-repo.sh" "${dest_repo}" "Automatically created for branch copy from ${source_repo}" false
  
  if [ $? -ne 0 ]; then
    echo "🔴 error: failed to create destination repository ${dest_repo}"
    exit 1
  fi
  
  # Verify the repository was created successfully
  echo "Re-verifying destination repository ${dest_repo}..."
  DEST_REPO_RECHECK_RESPONSE=$(curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/${dest_repo} 2> /dev/null)
  if [ -n "${DEBUG}" ]; then
    echo "🐛 Destination repo recheck API response: ${DEST_REPO_RECHECK_RESPONSE}"
  fi
  DEST_REPO_CHECK=$(echo "${DEST_REPO_RECHECK_RESPONSE}" | jq -r '.full_name // ""')
  if [ -z "${DEST_REPO_CHECK}" ]; then
    echo "🔴 error: destination repository ${dest_repo} still not accessible after creation"
    if [ -n "${DEBUG}" ]; then
      echo "🐛 Recheck response: ${DEST_REPO_RECHECK_RESPONSE}"
    fi
    exit 1
  fi
  
  echo "✅ Repository ${dest_repo} created successfully"
fi

echo "✅ Both repositories are accessible"

# Create a temporary directory for the operation
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Cleanup function
cleanup() {
  echo "Cleaning up temporary directory..."
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Clone the source repository
echo "Cloning source repository ${source_repo}..."
git clone "https://${GITHUB_TOKEN}@github.com/${source_repo}.git" source-repo
cd source-repo

# Checkout the source branch
echo "Checking out source branch ${source_branch}..."
git checkout "${source_branch}"

# Add destination repo as a remote
echo "Adding destination repository ${dest_repo} as remote..."
git remote add destination "https://${GITHUB_TOKEN}@github.com/${dest_repo}.git"

# Check if destination branch already exists
echo "Checking if destination branch ${dest_branch} already exists..."
if git ls-remote --heads destination "${dest_branch}" | grep -q "${dest_branch}"; then
  echo "⚠️  Branch ${dest_branch} already exists in ${dest_repo}"
  echo "   You may want to use a different branch name or delete the existing branch first"
  exit 1
fi

# Push the branch to destination repo
echo "Pushing ${source_branch} to ${dest_repo} as ${dest_branch}..."
git push destination "${source_branch}:${dest_branch}"

# Verify the branch was created successfully
echo "Verifying that branch ${dest_branch} exists in ${dest_repo}..."
if git ls-remote --heads destination "${dest_branch}" | grep -q "${dest_branch}"; then
  DEST_SHA=$(git ls-remote --heads destination "${dest_branch}" | cut -f1)
  SOURCE_SHA=$(git rev-parse HEAD)
  
  echo "✅ Branch successfully copied to ${dest_repo}"
  echo "   - Source: ${source_repo}:${source_branch} (${SOURCE_SHA})"
  echo "   - Destination: ${dest_repo}:${dest_branch} (${DEST_SHA})"
  
  if [ "${SOURCE_SHA}" = "${DEST_SHA}" ]; then
    echo "   - SHA verification: ✅ Match"
  else
    echo "   - SHA verification: ⚠️  Different (this may be expected if repos have different history)"
  fi
else
  echo "🔴 error: failed to verify that branch ${dest_branch} was created in ${dest_repo}"
  exit 1
fi

echo "🎉 Branch copy completed successfully!"
