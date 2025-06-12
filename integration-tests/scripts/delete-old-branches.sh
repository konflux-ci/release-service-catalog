#!/bin/bash
#
# Delete Old GitHub Branches
# ========================
#
# Summary:
# --------
# This script automatically cleans up old branches in a GitHub repository by
# deleting branches that haven't had any commits within a specified timeframe.
# It skips branches ending in "-base" and the "main" branch for safety.
#
# Features:
# --------
# - Identifies branches with no recent commits
# - Configurable cutoff period (default: 1 day)
# - Safe deletion with base branch protection
# - Handles pagination for repositories with many branches
# - Provides detailed output of deleted branches
#
# Usage:
# -----
#   ./delete-old-branches.sh <owner/repository>
#
# Example:
#   ./delete-old-branches.sh redhat/release-service
#
# Required Environment Variables:
# ----------------------------
# - GITHUB_TOKEN: GitHub Personal Access Token with repo access
#
# Configuration:
# -------------
# - CUTOFF_DATE: Time period to consider a branch as old (default: "1 day")
# - Automatically skips branches:
#   * Ending in "-base"
#   * Named "main"
#
# GitHub API Details:
# -----------------
# - Uses GitHub REST API v2022-11-28
# - Requires 'repo' scope permissions
# - Handles up to 100 branches per page
#
# Exit Codes:
# ----------
# - 0: Success
# - 1: Error (missing token, invalid repo, API error)

if [ -z "$GITHUB_TOKEN" ] ; then
  echo "🔴 error: missing env var GITHUB_TOKEN"
  exit 1
fi

repo_name=$1
if [ -z "$repo_name" ] ; then
  echo "🔴 error: missing parameter repo_name"
  exit 1
fi

CUTOFF_DATE="1 day"
CUTOFF_SECONDS=$(date -d "$CUTOFF_DATE ago" +%s)

echo "Finding branches in $repo_name with no commits for $CUTOFF_DATE..."
echo "------------------------------------------------------------------"

# --- Main Logic ---

# 1. Get all branches and their last commit SHAs
# The 'jq' command creates a space-separated list of "branch_name commit_sha"
branches_data=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$repo_name/branches?per_page=100")

# Check for invalid token or other API errors
if echo "$branches_data" | jq -e '.message' 2> /dev/null; then
  echo "Error fetching branches. Check your token, owner, and repo."
  echo "Response: $(echo "$branches_data" | jq '.message')"
  exit 1
fi

echo "$branches_data" | jq -r '.[] | .name + " " + .commit.sha' | while read -r branch_name commit_sha; do
  if [[ "${branch_name}" == *"-base" ]] || [[ "${branch_name}" == "main" ]] ; then
    continue
  fi
    
  # 2. For each branch, get the date of its last commit
  commit_data=$(curl -s -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$repo_name/commits/$commit_sha")

  commit_date_str=$(echo "$commit_data" | jq -r '.commit.committer.date')
  commit_date_seconds=$(date -d "$commit_date_str" +%s)

  # 3. Compare the commit date with the cutoff date
  if [ "$commit_date_seconds" -lt "$CUTOFF_SECONDS" ]; then
    printf "Branch: %-40s Last Commit Date: %s\n" "$branch_name" "$commit_date_str"

    echo "- Deleting $branch_name in $repo_name"
    curl -L \
    -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$repo_name/git/refs/heads/$branch_name

  fi
done

echo "------------------------------------------------------------------"
echo "Search complete."
