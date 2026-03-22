#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"

kubectl delete secret filter-advisory-rpms-secret --ignore-not-found
kubectl create secret generic filter-advisory-rpms-secret \
  --from-literal=git_author_email=tester@tester \
  --from-literal=git_author_name=tester \
  --from-literal=gitlab_access_token=abc \
  --from-literal=gitlab_host=myurl \
  --from-literal=git_repo=https://gitlab.com/org/repo.git
