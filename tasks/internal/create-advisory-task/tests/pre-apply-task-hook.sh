#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"

kubectl delete secret create-advisory-secret --ignore-not-found
kubectl create secret generic create-advisory-secret --from-literal=git_author_email=tester@tester --from-literal=git_author_name=tester --from-literal=gitlab_access_token=abc --from-literal=gitlab_host=myurl --from-literal=git_repo=https://gitlab.com/org/repo.git

kubectl delete secret create-stage-advisory-secret --ignore-not-found
kubectl create secret generic create-stage-advisory-secret --from-literal=git_author_email=tester@tester --from-literal=git_author_name=tester --from-literal=gitlab_access_token=abc --from-literal=gitlab_host=myurl --from-literal=git_repo=https://gitlab.com/rhtap-release/repo.git

kubectl delete secret create-advisory-errata-secret --ignore-not-found
kubectl create secret generic create-advisory-errata-secret --from-literal=errata_api=https://errata/api/v1 --from-literal=name=errata-tester --from-literal=base64_keytab=Zm9vCg==
