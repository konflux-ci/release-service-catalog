#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add test setup and mocks to the beginning of the sign-files step script (step[2])
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/test-setup.sh") + load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

# Create dummy secrets
kubectl delete secret my-mocked-secret --ignore-not-found
kubectl create secret generic my-mocked-secret --from-literal=signHost=mysigning.mock.com \
        --from-literal=signKey=my-mock-signing-key \
        --from-literal=signUser=my-mock-keytab-user
echo -e "\0005\0002\c" > my-mock.keytab
echo "1.2.3.4 my-mock-host" > checksumFingerprint
kubectl delete secret build-and-sign-keytab --ignore-not-found 
kubectl create secret generic build-and-sign-keytab --from-file=my-mock.keytab
kubectl delete secret checksum-fingerprint --ignore-not-found
kubectl create secret generic checksum-fingerprint --from-file=checksumFingerprint
