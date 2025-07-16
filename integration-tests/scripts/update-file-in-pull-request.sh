#!/usr/bin/env bash
#
# Summary:
#   Updates an existing file in a specified pull request in a GitHub repository.
#
# Parameters:
#   $1: repo_name    - The name of the GitHub repository (e.g., "owner/repo").
#   $2: pr_number    - The number of the pull request to update.
#   $3: file_name    - The desired name for the new file within the repository.
#   $4: commit_msg   - The commit message to use.
#   $5: encoded_contents - The encoded contents of the file to update.
#
# Environment Variables:
#   GH_TOKEN   - A GitHub personal access token with permissions to write to
#                    the repository. Required.
#
# Dependencies:
#   curl, jq, mktemp

set -eo pipefail

if [ -z $GH_TOKEN ] ; then
  echo "error: missing env var GH_TOKEN"
  exit 1
fi

repo_name=$1
if [ -z "$repo_name" ] ; then
  echo "🔴 error: missing parameter repo_name"
  exit 1
fi
pr_number=$2
if [ -z "$pr_number" ] ; then
  echo "🔴 error: missing parameter pr_number"
  exit 1
fi
file_name=$3
if [ -z "$file_name" ] ; then
  echo "🔴 error: missing parameter file_name"
  exit 1
fi
commit_msg=$4
if [ -z "$commit_msg" ] ; then
  echo "🔴 error: missing parameter commit_msg"
  exit 1
fi
tmpFile=$(mktemp)

encoded_contents="$5"
if [ -z "$encoded_contents" ] ; then
  echo "🔴 error: missing parameter encoded_contents"
  exit 1
fi

echo "Updating an existing file ${file_name} in PR ${pr_number}"
# Get PR head branch info
pr_info=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
  "https://api.github.com/repos/${repo_name}/pulls/${pr_number}")
head_branch=$(jq -r '.head.ref' <<< "${pr_info}")
head_repo=$(jq -r '.head.repo.full_name' <<< "${pr_info}")

# Get current file SHA
file_sha=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
  "https://api.github.com/repos/${head_repo}/contents/${file_name}?ref=${head_branch}" \
  | jq -r '.sha')

# Update the file
response=$(curl -s -w "\n%{http_code}" -X PUT \
  -H "Authorization: token ${GH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "'"${commit_msg}"'",
    "content": "'"${encoded_contents}"'",
    "sha": "'"${file_sha}"'",
    "branch": "'"${head_branch}"'"
  }' \
  "https://api.github.com/repos/${head_repo}/contents/${file_name}")

code=$(echo "$response" | tail -n1)
[[ "$code" == "200" ]] && { echo "✅️ file ${file_name} updated in PR ${pr_number}"; exit 0; }
echo "🔴 error: Update failed: $3 (HTTP $code)"
echo "$response" | head -n -1 | jq -r '.message // empty' 2>/dev/null
exit 1
