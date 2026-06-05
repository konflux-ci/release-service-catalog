#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-publish-pyxis-repository-cert --ignore-not-found
kubectl create secret generic test-publish-pyxis-repository-cert \
  --from-literal=cert=mycert \
  --from-literal=key=mykey
