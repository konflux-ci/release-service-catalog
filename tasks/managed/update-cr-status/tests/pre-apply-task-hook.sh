#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# Create a dummy configmap for the trusted-ca volume (and delete it first if it exists)
kubectl delete configmap trusted-ca --ignore-not-found
kubectl create configmap trusted-ca --from-literal=ca-bundle.crt=dummy-cert
