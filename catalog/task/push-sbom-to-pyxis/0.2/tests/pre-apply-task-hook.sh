#!/usr/bin/env bash

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-push-sbom-to-pyxis-cert --ignore-not-found
kubectl create secret generic test-push-sbom-to-pyxis-cert --from-literal=cert=mycert --from-literal=key=mykey
