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

if [ -z "${GH_TOKEN:-}" ]; then
  echo "error: missing env var GH_TOKEN"
  exit 1
fi

repo_name=$1
if [ -z "${repo_name}" ]; then
  echo "🔴 error: missing parameter repo_name"
  exit 1
fi
pr_number=$2
if [ -z "${pr_number}" ]; then
  echo "🔴 error: missing parameter pr_number"
  exit 1
fi
file_name=$3
if [ -z "${file_name}" ]; then
  echo "🔴 error: missing parameter file_name"
  exit 1
fi
commit_msg=$4
if [ -z "${commit_msg}" ]; then
  echo "🔴 error: missing parameter commit_msg"
  exit 1
fi
encoded_contents=$5
if [ -z "${encoded_contents}" ]; then
  echo "🔴 error: missing parameter encoded_contents"
  exit 1
fi

echo "Updating an existing file ${file_name} in PR ${pr_number}"

if ! pr_info=$(curl -sS --retry 3 --retry-all-errors --fail-with-body \
    -H "Authorization: token ${GH_TOKEN}" \
    "https://api.github.com/repos/${repo_name}/pulls/${pr_number}"); then
  echo "🔴 error: GitHub API request failed when fetching PR ${pr_number} in ${repo_name}" >&2
  [ -n "${pr_info}" ] && echo "${pr_info}" >&2
  exit 1
fi
if ! jq -e . >/dev/null 2>&1 <<< "${pr_info}"; then
  echo "🔴 error: non-JSON response when fetching PR ${pr_number}: ${pr_info}" >&2
  exit 1
fi
head_branch=$(jq -r '.head.ref' <<< "${pr_info}")
head_repo=$(jq -r '.head.repo.full_name' <<< "${pr_info}")

if ! contents_response=$(curl -sS --retry 3 --retry-all-errors --fail-with-body \
    -H "Authorization: token ${GH_TOKEN}" \
    "https://api.github.com/repos/${head_repo}/contents/${file_name}?ref=${head_branch}"); then
  echo "🔴 error: GitHub API request failed when fetching ${file_name}" >&2
  [ -n "${contents_response}" ] && echo "${contents_response}" >&2
  exit 1
fi
if ! jq -e . >/dev/null 2>&1 <<< "${contents_response}"; then
  echo "🔴 error: non-JSON response when fetching ${file_name}: ${contents_response}" >&2
  exit 1
fi
file_sha=$(jq -r '.sha' <<< "${contents_response}")

if ! response=$(curl -sS --retry 3 -w "\n%{http_code}" -X PUT \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "message": "'"${commit_msg}"'",
      "content": "'"${encoded_contents}"'",
      "sha": "'"${file_sha}"'",
      "branch": "'"${head_branch}"'"
    }' \
    "https://api.github.com/repos/${head_repo}/contents/${file_name}"); then
  echo "🔴 error: GitHub API request failed when updating ${file_name}" >&2
  [ -n "${response}" ] && echo "${response}" >&2
  exit 1
fi

code=$(echo "${response}" | tail -n1)
body=$(echo "${response}" | sed '$d')
if [[ "${code}" == "200" ]]; then
  echo "✅️ file ${file_name} updated in PR ${pr_number}"
  exit 0
fi

echo "🔴 error: Update failed: ${file_name} (HTTP ${code})" >&2
if jq -e . >/dev/null 2>&1 <<< "${body}"; then
  jq -r '.message // empty' <<< "${body}" >&2
else
  echo "${body}" >&2
fi
exit 1
