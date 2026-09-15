#!/usr/bin/env bash

set -eux

# The task mounts these secrets before its step starts. The happy-path test
# uses empty components, so these credentials only need valid fixture keys.

kubectl delete secret mac-ssh-key --ignore-not-found
kubectl create secret generic mac-ssh-key \
  --from-literal=mac_id_rsa=dummy-key \
  --from-literal=mac_fingerprint=SHA256:dummyfingerprint

kubectl delete secret windows-ssh-key --ignore-not-found
kubectl create secret generic windows-ssh-key \
  --from-literal=windows_id_rsa=dummy-key \
  --from-literal=windows_fingerprint=SHA256:dummyfingerprint

kubectl delete secret mac-host-credentials --ignore-not-found
kubectl create secret generic mac-host-credentials \
  --from-literal=username=testuser \
  --from-literal=host=testhost

kubectl delete secret mac-signing-credentials --ignore-not-found
kubectl create secret generic mac-signing-credentials \
  --from-literal=keychain_password=testpass \
  --from-literal=signing_identity=testidentity \
  --from-literal=apple_id=testid \
  --from-literal=team_id=testteamid \
  --from-literal=app_specific_password=testapppassword

kubectl delete secret windows-credentials --ignore-not-found
kubectl create secret generic windows-credentials \
  --from-literal=username=testuser \
  --from-literal=port=22 \
  --from-literal=host=testhost

kubectl delete secret redhat-workloads-token --ignore-not-found
kubectl create secret generic redhat-workloads-token \
  --from-literal=.dockerconfigjson='{"auths":{}}'

kubectl delete secret quay-credentials --ignore-not-found
kubectl create secret generic quay-credentials \
  --from-literal=username=testuser \
  --from-literal=password=testpass
