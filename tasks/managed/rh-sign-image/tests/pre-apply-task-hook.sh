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

cat > "/tmp/configMap.json" << EOF
{
    "apiVersion": "v1",
    "data": {
        "PYXIS_URL": "https://pyxis.stage.engineering.redhat.com",
        "SIG_KEY_ID": "4096R/37036783 SHA-256",
        "SIG_KEY_NAME": "redhate2etesting",
        "PYXIS_SSL_CERT_FILE_NAME": "hacbs-signing-pipeline.pem",
        "PYXIS_SSL_CERT_SECRET_NAME": "hacbs-signing-pipeline-certs",
        "PYXIS_SSL_KEY_FILE_NAME": "hacbs-signing-pipeline.key",
        "UMB_CLIENT_NAME": "hacbs-signing-pipeline-nonprod",
        "UMB_LISTEN_TOPIC": "VirtualTopic.eng.robosignatory.hacbs.sign",
        "UMB_PUBLISH_TOPIC": "VirtualTopic.eng.hacbs-signing-pipeline.hacbs.sign",
        "UMB_URL": "umb.stage.api.redhat.com",
        "UMB_SSL_CERT_FILE_NAME": "hacbs-signing-pipeline.pem",
        "UMB_SSL_CERT_SECRET_NAME": "hacbs-signing-pipeline-certs",
        "UMB_SSL_KEY_FILE_NAME": "hacbs-signing-pipeline.key"
    },
    "kind": "ConfigMap",
    "metadata": {
        "name": "signing-config-map"
    }
}
EOF
kubectl delete cm/signing-config-map --ignore-not-found
kubectl create -f /tmp/configMap.json

cat > "/tmp/configMap2.json" << EOF
{
    "apiVersion": "v1",
    "data": {
        "PYXIS_URL": "https://pyxis.stage.engineering.redhat.com",
        "SIG_KEY_NAMES": "redhate2etesting redhate2etesting2",
        "PYXIS_SSL_CERT_FILE_NAME": "hacbs-signing-pipeline.pem",
        "PYXIS_SSL_CERT_SECRET_NAME": "hacbs-signing-pipeline-certs",
        "PYXIS_SSL_KEY_FILE_NAME": "hacbs-signing-pipeline.key",
        "UMB_CLIENT_NAME": "hacbs-signing-pipeline-nonprod",
        "UMB_LISTEN_TOPIC": "VirtualTopic.eng.robosignatory.hacbs.sign",
        "UMB_PUBLISH_TOPIC": "VirtualTopic.eng.hacbs-signing-pipeline.hacbs.sign",
        "UMB_URL": "umb.stage.api.redhat.com",
        "UMB_SSL_CERT_FILE_NAME": "hacbs-signing-pipeline.pem",
        "UMB_SSL_CERT_SECRET_NAME": "hacbs-signing-pipeline-certs",
        "UMB_SSL_KEY_FILE_NAME": "hacbs-signing-pipeline.key",
        "SIGNER_TYPE": "batch"
    },
    "kind": "ConfigMap",
    "metadata": {
        "name": "signing-config-map-multi-keys"
    }
}
EOF
kubectl delete cm/signing-config-map-multi-keys --ignore-not-found
kubectl create -f /tmp/configMap2.json

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
