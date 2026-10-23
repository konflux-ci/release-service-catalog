#!/usr/bin/env bash

kubectl delete secret quay-token-konflux-release-trusted-artifacts-secret --ignore-not-found

if [ -z "${DOCKER_CONFIG_JSON:-}" ]; then
  DOCKER_CONFIG_JSON=$(mktemp)
  echo -n '{"auths": {}}' > "${DOCKER_CONFIG_JSON}"
fi
echo "Using docker config stored in ${DOCKER_CONFIG_JSON}"
kubectl create secret generic quay-token-konflux-release-trusted-artifacts-secret \
  --from-file=.dockerconfigjson="${DOCKER_CONFIG_JSON}" \
  --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | kubectl apply -f -
