#!/usr/bin/env bash
set -euo pipefail

# The Conforma task used in the pipelines in this repo is accessed with a git
# resolver, pinned for stability with a specific git sha. This script is used
# to update the git sha across all the pipelines to the current latest konflux
# branch.
#
# See also this workflow which updates the konflux branch in that repo:
# https://github.com/conforma/infra-deployments-ci/actions/workflows/konflux-policy.yaml
#
# It's likely this will be used in another GitHub workflow to either create a
# PR with this update, or perhaps to push it directly, but at time of writing
# this is not yet implemented.

REPO_URL="https://github.com/conforma/tekton-catalog"
BRANCH="konflux"

NEW_REV=$(git ls-remote "${REPO_URL}" "refs/heads/${BRANCH}" | cut -f1)

if [[ -z "${NEW_REV}" ]]; then
    echo "Error: could not resolve HEAD of ${BRANCH} branch in ${REPO_URL}" >&2
    exit 1
fi

echo "Updating conforma/tekton-catalog revision to ${NEW_REV}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

count=0
while IFS= read -r file; do
    if sed -i -E \
        "/name: url/{N;/value: https:\/\/github\.com\/conforma\/tekton-catalog/{N;/name: revision/{N;s|(value: \")[a-f0-9]+(\")|\1${NEW_REV}\2|}}}" \
        "${file}"; then
        count=$((count + 1))
    fi
done < <(grep -rl "${REPO_URL}" "${REPO_ROOT}/pipelines/")

echo "Updated ${count} files"
