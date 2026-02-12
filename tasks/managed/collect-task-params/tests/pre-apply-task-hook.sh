#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

kubectl delete configmap --namespace konflux-info \
  -l "cm/cluster-config" \
  --timeout=30s || true
