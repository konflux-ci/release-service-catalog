#!/usr/bin/env bash
# Create a dummy infra-deployments-pr-creator secret and delete it if it already exists
kubectl delete secret infra-deployments-pr-creator --ignore-not-found
echo "fake-key" > fake-key.pem
kubectl create secret generic infra-deployments-pr-creator --from-file=private-key=fake-key.pem
