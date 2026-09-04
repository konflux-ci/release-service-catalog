#!/usr/bin/env bash
set -euo pipefail

kubectl delete secret file-updates-secret --ignore-not-found
kubectl create secret generic file-updates-secret \
  --from-literal=git_author_email=tester@tester \
  --from-literal=git_author_name=tester \
  --from-literal=gitlab_access_token=abc \
  --from-literal=gitlab_host=myurl
