#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"

# Create a dummy exodus secret (and delete it first if it exists)
kubectl delete secret pulp-task-exodus-secret --ignore-not-found
kubectl create secret generic pulp-task-exodus-secret --from-literal=cert=SENSITIVE_DATA_myexoduscert --from-literal=key=SENSITIVE_DATA_myexoduskey --from-literal=url=https://exodus.com

# Create a dummy pulp secret (and delete it first if it exists)
kubectl delete secret pulp-task-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-pulp-secret --from-literal=konflux-release-rhsm-pulp.crt=SENSITIVE_DATA_mypulpcert --from-literal=konflux-release-rhsm-pulp.key=SENSITIVE_DATA_mypulpkey --from-literal=pulp_url=https://pulp.com

# Create a dummy pulp secret to fail with (and delete it first if it exists)
# This is used to simulate the pulp_push_wrapper script failing
kubectl delete secret pulp-task-bad-pulp-secret --ignore-not-found
kubectl create secret generic pulp-task-bad-pulp-secret --from-literal=konflux-release-rhsm-pulp.crt=SENSITIVE_DATA_mypulpcert --from-literal=konflux-release-rhsm-pulp.key=SENSITIVE_DATA_mypulpkey --from-literal=pulp_url=https://failing-pulp.com

# Create a dummy udc secret (and delete it first if it exists)
kubectl delete secret pulp-task-udc-secret --ignore-not-found
kubectl create secret generic pulp-task-udc-secret --from-literal=cert=SENSITIVE_DATA_myudccert --from-literal=key=SENSITIVE_DATA_myudckey --from-literal=url=https://udc.com

# Create a dummy cgw secret (and delete it first if it exists)
kubectl delete secret pulp-task-cgw-secret --ignore-not-found
kubectl create secret generic pulp-task-cgw-secret --from-literal=username=SENSITIVE_DATA_cgwuser --from-literal=token=SENSITIVE_DATA_cgwtoken

# Create a dummy workloads secret (and delete it first if it exists)
# The secret name here is hardcoded in the task
kubectl delete secret redhat-workloads-token --ignore-not-found
kubectl create secret generic redhat-workloads-token --from-literal=.dockerconfigjson={"auths":{"quay.io":{"auth":"SENSITIVE_DATA_abcdefg"}}}
