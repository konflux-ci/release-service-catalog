#!/usr/bin/env bash

# Step layout:
#   [0] use-trusted-artifact (StepAction ref - no mock needed)
#   [1] publish-index-image (Python script - uses sitecustomize.py for mocking)
#   [2] create-trusted-artifact (StepAction ref - no mock needed)
#
# Managed task uses sitecustomize.py (auto-loaded by Python) to mock internal_request module.
# Mount python_mocks/ as ConfigMap and set PYTHONPATH so Python finds sitecustomize.py.

# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

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
