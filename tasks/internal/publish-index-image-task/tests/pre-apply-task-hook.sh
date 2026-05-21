#!/usr/bin/env bash

# Step layout:
#   [0] publish-index-image (Python script - mocks skopeo binary via tests/mocks/)
#
# Binary mocks from tests/mocks/ are embedded by render_python_task_mocks_from_yaml.py.
# Just need to create credentials secret.

# Create a dummy secret (and delete it first if it exists)
kubectl delete secret publish-index-image-secret --ignore-not-found
kubectl create secret generic publish-index-image-secret --from-literal=sourceIndexCredential=source --from-literal=targetIndexCredential=target
