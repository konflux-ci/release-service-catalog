#!/usr/bin/env bash

set -x

# Create a dummy slack-notification-secret secret (and delete it first if it exists)
kubectl delete secret my-secret --ignore-not-found

kubectl create secret generic my-secret --from-literal=my-team=ABCDEF
