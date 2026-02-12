#!/usr/bin/env bash

set -x
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Mount mocks as ConfigMap instead of prepending to each step script.
# This avoids the "argument list too long" error from Tekton's place-scripts
# init container. After the recent changes,
# the task scripts grew large enough that prepending 8KB mocks to each of the
# 7 steps pushed the base64-encoded sh -c argument over the ~131KB ARG_MAX.
kubectl delete configmap test-mocks --ignore-not-found
kubectl create configmap test-mocks --from-file=mocks.sh="$SCRIPT_DIR/mocks.sh"

# Add a volume for the mocks ConfigMap
yq -i '.spec.volumes += [{"name": "test-mocks", "configMap": {"name": "test-mocks"}}]' "$TASK_PATH"

# Add volumeMount and source line to each step
STEPS="$(yq '.spec.steps |length' "$TASK_PATH")"
for((i=0;i<STEPS;i++)); do
    # Add volumeMount to the step
    yq -i '.spec.steps['$i'].volumeMounts += [{"name": "test-mocks", "mountPath": "/mnt/test-mocks"}]' "$TASK_PATH"
    # Insert source command AFTER the shebang line (not before, or bash won't be used)
    yq -i '.spec.steps['$i'].script |= sub("^(#![^\n]*\n)", "${1}source /mnt/test-mocks/mocks.sh\n")' "$TASK_PATH"
done

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

# create ssh secrets

# cleaning up secrets first
for secret in checksum-credentials quay-credentials windows-credentials mac-host-credentials mac-signing-credentials; do
    kubectl delete secret "$secret" --ignore-not-found
done

TMPDIR=$(mktemp -d /tmp/XXXX.tmp)
for OS in windows mac; do
    ssh-keygen -f "${TMPDIR}/${OS}" -N ""
    kubectl delete secret "${OS}-ssh-key" --ignore-not-found
    kubectl create secret generic "${OS}-ssh-key" --from-file="${OS}_id_rsa=${TMPDIR}/${OS}" --from-literal="${OS}"_fingerprint="SENSITIVE_DATA_$(ssh-keygen -lf "${TMPDIR}/${OS}.pub")"
done
ssh-keygen -f "${TMPDIR}/checksum" -N ""
kubectl create secret generic "checksum-credentials" \
    --from-literal=keytab="U0VOU0lUSVZFX0RBVEFfZW1wdHkgLW4K" \
    --from-literal=user="konflux-release-signing-sa" \
    --from-literal=host="etera-worker.hosted.upshift.rdu2.redhat.com" \
    --from-literal=fingerprint="SENSITIVE_DATA_$(ssh-keygen -lf "${TMPDIR}/checksum.pub")"

# create quay, windows and mac secrets
kubectl create secret generic quay-credentials --from-literal=username="testuser" --from-literal=password="SENSITIVE_DATA_testpass"
kubectl create secret generic windows-credentials --from-literal=username="testuser" --from-literal=port="1234" --from-literal=host="testhost"
kubectl create secret generic mac-host-credentials --from-literal=username="testuser" --from-literal=host="testhost"
kubectl create secret generic mac-signing-credentials --from-literal=keychain_password="SENSITIVE_DATA_testkeychainpass" \
    --from-literal=signing_identity="SENSITIVE_DATA_testidentity" --from-literal=apple_id="SENSITIVE_DATA_testid" \
    --from-literal=team_id="SENSITIVE_DATA_testteamid" --from-literal=app_specific_password="SENSITIVE_DATA_testapppassword"

# clean up
rm -rf ${TMPDIR}
