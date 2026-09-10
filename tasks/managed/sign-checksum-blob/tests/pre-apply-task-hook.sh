#!/usr/bin/env bash
#
# Install the CRDs so the test infra can create/get/delete InternalRequests
.github/scripts/install_crds.sh

# Add RBAC so that the SA executing the tests can retrieve CRs
kubectl apply -f .github/resources/crd_rbac.yaml

# delete old InternalRequests
kubectl delete internalrequests --all -A

# The Python steps (command: sign_checksum_blob.py) are auto-rewritten by the
# test harness to prepend tests/mocks/ to PATH, so kubectl/oras/gpg/select-oci-auth
# are mocked without any yq injection here.
