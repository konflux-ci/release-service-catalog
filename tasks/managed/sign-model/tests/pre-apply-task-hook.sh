#!/usr/bin/env bash
#
# Create a dummy modelsignSecretName secret (and delete it first if it exists)
kubectl delete secret test-modelsign-secret test-modelsign-secret-rekor --ignore-not-found

export LD_LIBRARY_PATH="/usr/local/lib64/:$LD_LIBRARY_PATH"

openssl ecparam -name prime256v1 -genkey -noout -out key.pem
openssl ec -in key.pem -pubout -out public.pem

kubectl create secret generic test-modelsign-secret\
  --from-file=SIGN_KEY=key.pem\
  --from-file=PUBLIC_KEY=public.pem

kubectl create secret generic test-modelsign-secret-rekor\
  --from-file=SIGN_KEY=key.pem\
  --from-file=PUBLIC_KEY=public.pem

# Add mocks to the beginning of task step script
TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"
