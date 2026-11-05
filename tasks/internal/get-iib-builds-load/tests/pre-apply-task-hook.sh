#!/usr/bin/env bash

# The secret name is hardcoded in the task so the mock secret name can't have the task name in it.
# The url is replaced with the mock server's by mocks.yaml (rewrite_secret_mount).
kubectl delete secret iib-services-config --ignore-not-found
kubectl create secret generic iib-services-config --from-literal=url="https://fakeiib.host/api/v1"
