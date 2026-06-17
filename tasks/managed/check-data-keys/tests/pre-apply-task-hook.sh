#!/usr/bin/env bash

TASK_PATH="$1"

# Add RBAC so that the SA executing the tests can retrieve configMap
kubectl apply -f .github/resources/crd_rbac.yaml
