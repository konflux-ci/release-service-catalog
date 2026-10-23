#!/usr/bin/env bash
#
# Install the CRDs so the test infra can create/get/delete InternalRequests
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# Create the signing ConfigMap used by the checksum-signing tests
kubectl delete configmap signing-config-map --ignore-not-found
kubectl create configmap signing-config-map --from-literal=SIG_KEY_NAME=redhate2etesting --from-literal=KERBEROS_KEYTAB_SECRET=kerberos-keytab-secret --from-literal=KERBEROS_KEYTAB=keytab --from-literal=KERBEROS_PRINCIPAL=signing@EXAMPLE.COM

# The Python steps (command: sign_checksum_blob.py) are auto-rewritten by the
# test harness to prepend tests/mocks/ to PATH, so kubectl/oras/gpg/select-oci-auth
# are mocked without any yq injection here.
