#!/usr/bin/env bash

# Create the IIB service account secret (matching test parameter and upstream pattern)
kubectl create secret generic test-iib-service-account \
    --from-literal=keytab="$(echo 'fake-keytab-content' | base64)" \
    --from-literal=principal="fake-principal@REDHAT.COM" || true

# Create the iib-services-config secret
kubectl create secret generic iib-services-config \
    --from-literal=krb5.conf="[libdefaults]\n  default_realm = REDHAT.COM" \
    --from-literal=url="https://fakeiib.host" || true
