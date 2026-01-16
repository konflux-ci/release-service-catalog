#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[0].script = load_str("'$SCRIPT_DIR'/mocks.sh") + "set +x\n" + .spec.steps[0].script' "$TASK_PATH"

kubectl delete secret quay-token-konflux-release-trusted-artifacts-secret --ignore-not-found

if [ -z "${DOCKER_CONFIG_JSON}" ]; then
  DOCKER_CONFIG_JSON=$(mktemp)
  echo -n '{"auths": {"auths":{"quay.io":{"auth":"THIS_SHOULD_NOT_BE_EXPOSED"}}}}' > "${DOCKER_CONFIG_JSON}"
fi
echo "Using docker config stored in ${DOCKER_CONFIG_JSON}"
kubectl create secret generic quay-token-konflux-release-trusted-artifacts-secret \
  --from-file=.dockerconfigjson="${DOCKER_CONFIG_JSON}" \
  --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | kubectl apply -f -
