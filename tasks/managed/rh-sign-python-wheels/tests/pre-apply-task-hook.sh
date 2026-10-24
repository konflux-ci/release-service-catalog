#!/usr/bin/env bash

# Create a dummy AWS KMS secret (and delete it first if it exists)
kubectl delete secret test-aws-kms-secret --ignore-not-found
kubectl create secret generic test-aws-kms-secret \
  --from-literal=AWS_DEFAULT_REGION=us-east-1 \
  --from-literal=AWS_ACCESS_KEY_ID=test-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=test-secret-key \
  --from-literal=SIGN_KEY=awskms:///arn:aws:kms:us-east-1:123456789:key/test-key

