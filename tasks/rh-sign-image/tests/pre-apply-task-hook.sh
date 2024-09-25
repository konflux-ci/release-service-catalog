#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-create-pyxis-image-cert --ignore-not-found
kubectl create secret generic test-create-pyxis-image-cert --from-literal=cert=mycert --from-literal=key=mykey

# Delete pipeline for signing
kubectl delete pipeline/simple-signing-pipeline --ignore-not-found

cat > "/tmp/simple-signing-pipeline.json" << EOF
{
  "apiVersion": "tekton.dev/v1",
  "kind": "Pipeline",
  "metadata": {
    "name": "simple-signing-pipeline",
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
kubectl create -f /tmp/simple-signing-pipeline.json

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
