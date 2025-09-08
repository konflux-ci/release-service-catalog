#!/usr/bin/env bash

# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Delete pipeline for push-artifacts-to-cdn
kubectl delete pipeline/push-artifacts-to-cdn --ignore-not-found

cat > "/tmp/push-artifacts-to-cdn.json" << EOF
{
  "apiVersion": "tekton.dev/v1",
  "kind": "Pipeline",
  "metadata": {
    "name": "push-artifacts-to-cdn",
    "namespace": "default"
  },
  "spec": {
    "tasks": [
      {
        "name": "task1",
        "taskSpec": {
          "steps": [
            {
              "image": "bash:3.2",
              "name": "build",
              "script": "echo scott"
            }
          ]
        }
      }
    ]
  }
}
EOF
kubectl create -f /tmp/push-artifacts-to-cdn.json

cat > "/tmp/configmap.json" << EOF
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "test-config-map",
    "namespace": "default"
  },
  "data": {
    "SIG_KEY_ID": "testKey"
  }
}
EOF
kubectl apply -f /tmp/configmap.json

# Add mocks to the beginning of task step script
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
