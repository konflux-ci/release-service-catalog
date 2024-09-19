#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mac_mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[2].script' "$TASK_PATH"
yq -i '.spec.steps[3].script = load_str("'$SCRIPT_DIR'/checksum_mocks.sh") + .spec.steps[3].script' "$TASK_PATH"

# Delete existing secrets if they exist
kubectl delete secret windows-credentials --ignore-not-found
kubectl delete secret windows-ssh-key --ignore-not-found
kubectl delete secret mac-signing-credentials --ignore-not-found
kubectl delete secret mac-host-credentials --ignore-not-found
kubectl delete secret mac-ssh-key --ignore-not-found
kubectl delete secret quay-secret --ignore-not-found
kubectl delete secret checksum-fingerprint --ignore-not-found
kubectl delete secret checksum-keytab --ignore-not-found

# Create the windows-credentials secret
kubectl create secret generic windows-credentials \
    --from-literal=username=windowsusername \
    --from-literal=password=windowspass \
    --from-literal=port=22 \
    --from-literal=host=windowsserver.com \
    --namespace=default

# Create the windows-ssh-key secret
kubectl create secret generic windows-ssh-key \
    --from-literal=windows_id_rsa="windows private key" \
    --from-literal=windows_fingerprint="windows fingerprint" \
    --namespace=default

# Create the quay-secret secret
kubectl create secret generic quay-secret \
    --from-literal=username=myusername \
    --from-literal=password=mypass \
    --namespace=default

# Create the mac-host-credentials secret
kubectl create secret generic mac-host-credentials \
    --from-literal=host="mac_host" \
    --from-literal=username="mac_user" \
    --from-literal=mac-password="mac_password" \

# Create the mac-signing-credentials secret
kubectl create secret generic mac-signing-credentials \
    --from-literal=keychain_password="keychain_password" \
    --from-literal=signing_identity="signing_identity" \
    --from-literal=apple_id="apple_id" \
    --from-literal=app_specific_password="app_specific_password" \
    --from-literal=team_id="team_id" \

# Create the mac-ssh-key secret
kubectl create secret generic mac-ssh-key \
    --from-literal=mac_id_rsa="some private key" \
    --from-literal=mac_fingerprint="some fingerprint" \
    --namespace=default

# Create the checksum fingerprint
kubectl create secret generic checksum-fingerprint \
    --from-literal=fingerprint="some fingerprint" \
    --namespace=default

# Create the checksum keytab
kubectl create secret generic checksum-keytab \
    --from-literal=keytab="some keytab" \
    --namespace=default
