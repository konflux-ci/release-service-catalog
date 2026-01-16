#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-push-rpm-data-to-pyxis-cert --ignore-not-found
kubectl create secret generic test-push-rpm-data-to-pyxis-cert --from-literal=cert=SENSITIVE_DATA_mycert --from-literal=key=SENSITIVE_DATA_mykey

# Add mocks to the beginning of scripts
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[1].script' "$TASK_PATH"
yq -i '.spec.steps[2].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[2].script' "$TASK_PATH"
