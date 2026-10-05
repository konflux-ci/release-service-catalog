#!/usr/bin/env bash

set -euo pipefail

echo "Creating S3 mock secret..."

kubectl delete secret s3-mock-secret --ignore-not-found
kubectl create secret generic s3-mock-secret \
  --from-literal=aws_access_key_id=MOCK_AWS_KEY_ID \
  --from-literal=aws_secret_access_key=MOCK_AWS_SECRET_KEY
