#!/usr/bin/env bash

set -euxo pipefail

# CDN/publishing secrets
kubectl delete secret test-exodus-secret --ignore-not-found
kubectl create secret generic test-exodus-secret \
  --from-literal=cert=myfakecert \
  --from-literal=key=myfakekey \
  --from-literal=url=https://exodus.test.com

kubectl delete secret test-cgw-secret --ignore-not-found
kubectl create secret generic test-cgw-secret \
  --from-literal=username=cgwuser \
  --from-literal=token=cgwtoken

# Trusted Artifacts registry credential
kubectl delete secret quay-token-konflux-release-trusted-artifacts-secret --ignore-not-found
kubectl create secret docker-registry quay-token-konflux-release-trusted-artifacts-secret \
  --docker-server=quay.io \
  --docker-username=fake \
  --docker-password=fake
