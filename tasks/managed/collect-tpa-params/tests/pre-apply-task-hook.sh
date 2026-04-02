#!/usr/bin/env bash

# Add RBAC so that the SA executing the tests can manage configmaps
kubectl apply -f .github/resources/crd_rbac.yaml
