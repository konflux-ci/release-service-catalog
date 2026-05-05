#!/usr/bin/env bash

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Inject mocks into all step scripts
num_steps=$(yq '.spec.steps | length' "$TASK_PATH")
for i in $(seq 0 $((num_steps - 1))); do
  yq -i '.spec.steps['$i'].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps['$i'].script' "$TASK_PATH"
done

# Replace emptyDir volume with workspace for testing
# The production task uses emptyDir mounted at /workspace/data for inter-step data sharing,
# but tests need a workspace to verify mock calls by sharing data with the check-result task.
# Since Tekton mounts workspaces at /workspace/<name> by default, a workspace named "data"
# will mount at /workspace/data - the same path as the emptyDir - so no path changes needed.
yq -i 'del(.spec.volumes[] | select(.name == "workspace-data"))' "$TASK_PATH"
yq -i 'del(.spec.stepTemplate.volumeMounts[] | select(.name == "workspace-data"))' "$TASK_PATH"
yq -i '.spec.workspaces += [{"name": "data"}]' "$TASK_PATH"

# Create a dummy secret for ssl cert for pyxis interactions (and delete it first if it exists)
kubectl delete secret pyxis-ssl-cert --ignore-not-found
kubectl create secret generic pyxis-ssl-cert --from-literal=cert=mypyxiscert --from-literal=key=mypyxiskey

# Create a dummy secret for ssl cert for UMB interactions (and delete it first if it exists)
kubectl delete secret umb-ssl-cert --ignore-not-found
kubectl create secret generic umb-ssl-cert --from-literal=cert=myumbcert --from-literal=key=myumbkey
