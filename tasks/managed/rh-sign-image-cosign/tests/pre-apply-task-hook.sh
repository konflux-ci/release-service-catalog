#!/usr/bin/env bash
set -euo pipefail
#
# Create a dummy cosignSecretName secret (and delete it first if it exists)
kubectl delete secret test-cosign-secret test-cosign-secret-rekor --ignore-not-found

kubectl create secret generic test-cosign-secret\
  --from-literal=AWS_DEFAULT_REGION=us-test-1\
  --from-literal=AWS_ACCESS_KEY_ID=test-access-key\
  --from-literal=AWS_SECRET_ACCESS_KEY=test-secret-access-key\
  --from-literal=SIGN_KEY=aws://arn:mykey\
  --from-literal=REKOR_PUBLIC_KEY=rekor_public_key\
  --from-literal=PUBLIC_KEY=public_key

kubectl create secret generic test-cosign-secret-rekor\
  --from-literal=AWS_DEFAULT_REGION=us-test-1\
  --from-literal=AWS_ACCESS_KEY_ID=test-access-key\
  --from-literal=AWS_SECRET_ACCESS_KEY=test-secret-access-key\
  --from-literal=SIGN_KEY=aws://arn:mykey\
  --from-literal=REKOR_URL=https://fake-rekor-server\
  --from-literal=REKOR_PUBLIC_KEY=rekor_public_key\
  --from-literal=PUBLIC_KEY=public_key

# Inject PARAMS_DATA_DIR into the sign-image step (step index 1) so the mock
# binaries embedded by mocks.yaml can write call-log files to the shared data dir.
TASK_PATH="$1"
yq -i '.spec.steps[1].env += [{"name": "PARAMS_DATA_DIR", "value": "$(params.dataDir)"}]' \
    "${TASK_PATH}"
