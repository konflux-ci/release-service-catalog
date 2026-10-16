#!/usr/bin/env bash

# 1. Define the secret name used in your test YAML
MARKETPLACE_SECRET="marketplacesvm-test-secret"

# 2. Delete the secret if it already exists to ensure a clean state
kubectl delete secret "$MARKETPLACE_SECRET" --ignore-not-found

# 3. Create the generic secret
# Each --from-literal key will become a filename inside /etc/secrets/
kubectl create secret generic "$MARKETPLACE_SECRET" \
  --from-literal=aws-na.json='{
    "marketplace_account": "aws-na",
    "auth": {
        "AWS_IMAGE_ACCESS_KEY": "AK-TEST-NA",
        "AWS_IMAGE_SECRET_ACCESS": "sa-test-na-secret",
        "AWS_MARKETPLACE_ACCESS_KEY": "AK-TEST-NA-MKT",
        "AWS_MARKETPLACE_SECRET_ACCESS": "sa-test-na-mkt-secret",
        "AWS_ACCESS_ROLE_ARN": "arn:aws:iam::555555555555:role/AWSMarketplaceScanning",
        "AWS_GROUPS": [],
        "AWS_SNAPSHOT_ACCOUNTS": [],
        "AWS_REGION": "us-east-1"
    }
}' \
  --from-literal=aws-emea.json='{
    "marketplace_account": "aws-emea",
    "auth": {
        "AWS_IMAGE_ACCESS_KEY": "AK-TEST-EMEA",
        "AWS_IMAGE_SECRET_ACCESS": "sa-test-emea-secret",
        "AWS_MARKETPLACE_ACCESS_KEY": "AK-TEST-EMEA-MKT",
        "AWS_MARKETPLACE_SECRET_ACCESS": "sa-test-emea-mkt-secret",
        "AWS_ACCESS_ROLE_ARN": "arn:aws:iam::555555555555:role/AWSMarketplaceScanning",
        "AWS_GROUPS": [],
        "AWS_SNAPSHOT_ACCOUNTS": [],
        "AWS_REGION": "eu-central-1"
    }
}'
