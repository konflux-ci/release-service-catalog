#!/usr/bin/env bash

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

cat > "/tmp/cm.json" << EOF
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
        "name": "create-advisory-test-cm"
    }
}
EOF
kubectl delete -f /tmp/cm.json --ignore-not-found
kubectl create -f /tmp/cm.json

kubectl delete secret create-advisory-secret --ignore-not-found
kubectl create secret generic create-advisory-secret \
    --from-literal=git_author_email=tester@tester \
    --from-literal=git_author_name=tester \
    --from-literal=gitlab_access_token=abc \
    --from-literal=gitlab_host=myurl \
    --from-literal=git_repo=https://gitlab.com/org/repo.git

kubectl delete secret create-advisory-errata-secret --ignore-not-found
kubectl create secret generic create-advisory-errata-secret \
    --from-literal=errata_api=https://errata/api/v1 \
    --from-literal=name=errata-tester \
    --from-literal=base64_keytab=Zm9vCg==
