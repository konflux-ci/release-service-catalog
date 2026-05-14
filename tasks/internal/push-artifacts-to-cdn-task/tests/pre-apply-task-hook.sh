#!/usr/bin/env bash

set -ex

# Create redhat-workloads-token secret used by extract_artifacts for docker auth
kubectl delete secret redhat-workloads-token --ignore-not-found
kubectl create secret generic redhat-workloads-token \
  --from-literal=.dockerconfigjson='{"auths":{"quay.io":{"auth":"dGVzdDp0ZXN0"}}}'

# Create Quay credential secret used by push_unsigned and compress_artifacts
kubectl delete secret quay-credentials --ignore-not-found
kubectl create secret generic quay-credentials \
  --from-literal=username=testuser \
  --from-literal=password=testpass

# Create SSH key secrets with dummy values (mocks don't use actual keys)
for OS in mac windows; do
  kubectl delete secret "${OS}-ssh-key" --ignore-not-found
  kubectl create secret generic "${OS}-ssh-key" \
    --from-literal="${OS}_id_rsa=dummy-key" \
    --from-literal="${OS}_fingerprint=SHA256:dummyfingerprint"
done

kubectl delete secret checksum-credentials --ignore-not-found
kubectl create secret generic checksum-credentials \
  --from-literal=keytab="" \
  --from-literal=user=test-checksum-user \
  --from-literal=host=test-checksum-host \
  --from-literal=fingerprint="SHA256:dummyfingerprint"

# Mac signing host secrets
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

# Windows signing host secret
kubectl delete secret windows-credentials --ignore-not-found
kubectl create secret generic windows-credentials \
  --from-literal=username=testuser \
  --from-literal=port=22 \
  --from-literal=host=testhost

# CDN/publishing secrets
kubectl delete secret pulp-task-exodus-secret --ignore-not-found
kubectl create secret generic pulp-task-exodus-secret \
  --from-literal=cert=myfakecert \
  --from-literal=key=myfakekey \
  --from-literal=url=https://exodus.test.com

kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret \
  --from-literal=konflux-release-rhsm-pulp.crt=myfakecert \
  --from-literal=konflux-release-rhsm-pulp.key=myfakekey \
  --from-literal=pulp_url=https://pulp.test.com

kubectl delete secret pulp-task-udc-secret --ignore-not-found
kubectl create secret generic pulp-task-udc-secret \
  --from-literal=cert=myfakecert \
  --from-literal=key=myfakekey \
  --from-literal=url=https://udc.test.com

kubectl delete secret pulp-task-cgw-secret --ignore-not-found
kubectl create secret generic pulp-task-cgw-secret \
  --from-literal=username=cgwuser \
  --from-literal=token=cgwtoken
