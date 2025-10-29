#!/bin/bash

TASK_PATH=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' $TASK_PATH

# Create a dummy configmap for the trusted-ca volume (and delete it first if it exists)
kubectl delete configmap trusted-ca --ignore-not-found
kubectl create configmap trusted-ca --from-literal=ca-bundle.crt=dummy-cert

