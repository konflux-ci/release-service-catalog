#!/usr/bin/env bash
set -euo pipefail

kubectl delete secret test-push-rpm-data-to-pyxis-cert --ignore-not-found
kubectl create secret generic test-push-rpm-data-to-pyxis-cert --from-literal=cert=mycert --from-literal=key=mykey
