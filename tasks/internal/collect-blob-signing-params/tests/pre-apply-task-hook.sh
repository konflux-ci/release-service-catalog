#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml


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
        "name": "hacbs-signing-pipeline-config-example"
    }
}
EOF
kubectl delete cm/hacbs-signing-pipeline-config-example --ignore-not-found
kubectl create -f /tmp/configMap.json
