#!/usr/bin/env bash
set -euo pipefail

yq -i '.spec.steps[1].env += [{"name": "DATA_DIR", "value": "$(params.dataDir)"}]' "$1"

kubectl apply -f .github/resources/crd_rbac.yaml

kubectl delete configmap signing-config-map --ignore-not-found
kubectl create configmap signing-config-map \
    --from-literal=SIG_KEY_NAME=redhate2etesting \
    --from-literal=KERBEROS_KEYTAB_SECRET=kerberos-keytab-secret \
    --from-literal=KERBEROS_KEYTAB=/etc/kerberos/keytab \
    --from-literal=KERBEROS_PRINCIPAL=signing@EXAMPLE.COM

