#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[0].script' $SCRIPT_DIR/../publish-pyxis-repository.yaml

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-publish-pyxis-repository-cert --ignore-not-found
kubectl create secret generic test-publish-pyxis-repository-cert --from-literal=cert=mycert --from-literal=key=mykey
