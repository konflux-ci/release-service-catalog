#!/usr/bin/env bash
set -euo pipefail

kubectl delete secret filter-already-released-advisory-images-secret --ignore-not-found
kubectl create secret generic filter-already-released-advisory-images-secret \
  --from-literal=git_author_email=tester@tester \
  --from-literal=git_author_name=tester \
  --from-literal=gitlab_access_token=abc \
  --from-literal=gitlab_host=myurl \
  --from-literal=git_repo=https://gitlab.com/org/repo.git
