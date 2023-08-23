#!/usr/bin/env bash
set -eux

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

TASK_NAME=$1

# Create a dummy pyxis secret (and delete it first if it exists)
kubectl delete secret test-push-sbom-to-pyxis-cert --ignore-not-found
kubectl create secret generic test-push-sbom-to-pyxis-cert --from-literal=cert=mycert --from-literal=key=mykey

cd $SCRIPT_DIR

# Create a backup of the original task file
cp ../${TASK_NAME}.yaml ../${TASK_NAME}.yaml.orig


# Inject image with mocks to steps 0 and 1
for STEP in 0 1; do
    ORIG_IMAGE=$(yq ".spec.steps[${STEP}].image" ../${TASK_NAME}.yaml)
    TAR_FILE=${TASK_NAME}-${STEP}.tar
    podman build -t ${TASK_NAME}:${STEP} --build-arg BASE_IMAGE=$ORIG_IMAGE .
    podman save -o $TAR_FILE ${TASK_NAME}:${STEP}
    kind load image-archive $TAR_FILE
    yq -i ".spec.steps[${STEP}].image = \"localhost/${TASK_NAME}:${STEP}\"" ../${TASK_NAME}.yaml
    yq -i ".spec.steps[${STEP}].env += "'[{"name": "WORKSPACE_DIR", "value": "$(workspaces.data.path)"}]' ../push-sbom-to-pyxis.yaml
done
