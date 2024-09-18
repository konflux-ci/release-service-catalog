#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' "$TASK_PATH"
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Delete existing secrets if they exist
kubectl delete secret windows-credentials --ignore-not-found
kubectl delete secret windows-ssh-key --ignore-not-found
kubectl delete secret mac-signing-credentials --ignore-not-found
kubectl delete secret mac-host-credentials --ignore-not-found
kubectl delete secret mac-ssh-key --ignore-not-found
kubectl delete secret quay-secret --ignore-not-found
# Create the windows-credentials secret
kubectl create secret generic windows-credentials \
    --from-literal=username=myusername \
    --from-literal=password=mypass \
    --from-literal=port=22 \
    --from-literal=host=myserver.com \
    --namespace=default

# Create the windows-ssh-key secret
kubectl create secret generic windows-ssh-key \
    --from-literal=id_rsa="some private key" \
    --from-literal=fingerprint="some fingerprint" \
    --namespace=default

# Create the quay-secret secret
kubectl create secret generic quay-secret \
    --from-literal=username=myusername \
    --from-literal=password=mypass \
    --namespace=default

# Create the mac-host-credentials secret
kubectl create secret generic mac-host-credentials \
    --from-literal=mac-host="some_host" \
    --from-literal=mac-user="some_user" \
    --from-literal=mac-password="some_password" \

# Create the mac-signing-credentials secret
kubectl create secret generic mac-signing-credentials \
    --from-literal=keychain_password="some_password" \
    --from-literal=signing_identity="some_identity" \
    --from-literal=apple_id="some_id" \
    --from-literal=app_specific_password="some_password" \
    --from-literal=team_id="some_id" \

# Create the mac-ssh-key secret
kubectl create secret generic mac-ssh-key \
    --from-literal=id_rsa="some private key" \
    --from-literal=fingerprint="some fingerprint" \
    --namespace=default
