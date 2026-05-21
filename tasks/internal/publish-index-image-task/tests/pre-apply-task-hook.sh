#!/usr/bin/env bash

# Step layout:
#   [0] publish-index-image (Python script - uses sitecustomize.py for mocking)
#
# Internal task uses sitecustomize.py (auto-loaded by Python) to mock skopeo module.
# Mount python_mocks/ as ConfigMap and set PYTHONPATH so Python finds sitecustomize.py.

# Create a dummy secret (and delete it first if it exists)
kubectl delete secret publish-index-image-secret --ignore-not-found
kubectl create secret generic publish-index-image-secret --from-literal=sourceIndexCredential=source --from-literal=targetIndexCredential=target

# Mount python_mocks and set PYTHONPATH for Python-based task
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create ConfigMap with Python mocks
kubectl delete configmap python-mocks --ignore-not-found
kubectl create configmap python-mocks --from-file="${SCRIPT_DIR}/python_mocks/"

# Add volume for python_mocks
yq -i '.spec.volumes += [{"name": "python-mocks", "configMap": {"name": "python-mocks"}}]' "$TASK_PATH"

# Add volumeMount and PYTHONPATH to stepTemplate
yq -i '.spec.stepTemplate.volumeMounts += [{"name": "python-mocks", "mountPath": "/opt/python_mocks"}]' "$TASK_PATH"
yq -i '.spec.stepTemplate.env += [{"name": "PYTHONPATH", "value": "/opt/python_mocks"}]' "$TASK_PATH"
