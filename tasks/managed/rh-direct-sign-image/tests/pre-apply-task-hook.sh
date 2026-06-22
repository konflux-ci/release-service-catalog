#!/usr/bin/env bash
set -euo pipefail

# Inject DATA_DIR env var into the sign-image step so the internal-request mock
# binary can write its output to a location shared with the check-result step.
yq -i '.spec.steps[1].env += [{"name": "DATA_DIR", "value": "$(params.dataDir)"}]' "$1"

# Create pyxis secret (and delete it first if it exists)
kubectl delete secret test-pyxis-image-cert --ignore-not-found
kubectl create secret generic test-pyxis-image-cert --from-literal=cert=mycert --from-literal=key=mykey

# Grant the default service account RBAC permissions (needed in CI)
kubectl apply -f .github/resources/crd_rbac.yaml

# Create the signing ConfigMap that the script fetches via get_configmap()
kubectl delete configmap signing-config-map --ignore-not-found
kubectl create configmap signing-config-map \
    --from-literal=SIG_KEY_NAME=redhate2etesting \
    --from-literal=PYXIS_SSL_CERT_SECRET_NAME=test-pyxis-image-cert \
    --from-literal=PYXIS_GRAPHQL_URL=https://graphql-pyxis.api.redhat.com/graphql/ \
    --from-literal=KERBEROS_KEYTAB_SECRET=kerberos-keytab-secret \
    --from-literal=KERBEROS_KEYTAB=/etc/kerberos/keytab \
    --from-literal=KERBEROS_PRINCIPAL=signing@EXAMPLE.COM
