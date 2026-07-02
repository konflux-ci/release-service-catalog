#!/usr/bin/env bash
set -euo pipefail

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# Delete old InternalRequests
kubectl delete internalrequests --all -A --ignore-not-found

# Create a dummy pulp secret
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret \
  --from-literal=cli.toml='[cli]
base_url = "https://dummy.com"
username = "DUMMY"
password = "DUMMY"
'
