#!/usr/bin/env bash
#
# Install the CRDs so we can create/get them
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# create required secrets
kubectl create secret generic iib-service-account-secret \
    --from-literal=principal="iib@kerberos" \
    --from-literal=keytab="c29tZXRoaW5n"
kubectl create secret generic iib-services-config \
    --from-literal=krb5.conf="" \
    --from-literal=url="https://fakeiib.host"

kubectl create secret generic iib-overwrite-fromimage-credentials \
    --from-literal=username="bot+user" \
    --from-literal=token="token"
