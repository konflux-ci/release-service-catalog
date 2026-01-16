#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'"$SCRIPT_DIR"'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"

kubectl delete secret filter-already-released-advisory-images-secret --ignore-not-found
kubectl create secret generic filter-already-released-advisory-images-secret --from-literal=git_author_email=SENSITIVE_DATA_tester@tester --from-literal=git_author_name=SENSITIVE_DATA_tester --from-literal=gitlab_access_token=SENSITIVE_DATA_abc --from-literal=gitlab_host=SENSITIVE_DATA_myurl --from-literal=git_repo=SENSITIVE_DATA_https://gitlab.com/org/repo.git
