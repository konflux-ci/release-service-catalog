#!/usr/bin/env bash

# Add RBAC so that the SA executing the tests can create configMap
kubectl apply -f .github/resources/crd_rbac.yaml
