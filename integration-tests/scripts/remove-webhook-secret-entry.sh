#!/usr/bin/env bash
#
# Summary:
#   Removes a single repo's entry from pipelines-as-code-webhooks-secret. Uses a merge
#   patch so it only ever touches its own key.
# Parameters:
#   $1: namespace: Namespace containing the pipelines-as-code-webhooks-secret Secret.
#   $2: git_url: The repository's git URL e.g. https://github.com/org/repo
#

set -eo pipefail

namespace=$1
git_url=$2

secret_name="pipelines-as-code-webhooks-secret"

# PaC get the Secret's data key name from the repo URL by swapping : and / for _
secret_key="${git_url//[:\/]/_}"
patch=$(jq -nc --arg key "${secret_key}" '{data: {($key): null}}')

if [ -z "${namespace}" ] || [ -z "${git_url}" ]; then
  echo "error: missing parameter"
  echo "Usage: $0 <namespace> <git_url>"
  exit 1
fi

if ! kubectl get secret "${secret_name}" -n "${namespace}" > /dev/null 2>&1; then
  echo "info: Secret ${secret_name} not found in ${namespace}, nothing to clean up."
  exit 0
fi

echo "Removing key ${secret_key} from ${secret_name} in ${namespace}..."
kubectl patch secret "${secret_name}" -n "${namespace}" --type merge -p "${patch}"
