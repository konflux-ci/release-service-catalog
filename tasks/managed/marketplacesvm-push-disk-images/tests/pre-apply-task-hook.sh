#!/usr/bin/env bash

TASK_PATH="$1"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add mocks to the beginning of task step script
yq -i '.spec.steps[1].script = load_str("'$SCRIPT_DIR'/mocks.sh") + .spec.steps[1].script' "$TASK_PATH"

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

# 1. Define the secret name used in your test YAML
MARKETPLACE_SECRET="marketplacesvm-azure-test-secret"

# 2. Delete the secret if it already exists to ensure a clean state
kubectl delete secret "$MARKETPLACE_SECRET" --ignore-not-found

# 3. Create the generic secret
# Each --from-literal key will become a filename inside /etc/secrets/
kubectl create secret generic "$MARKETPLACE_SECRET" \
  --from-literal=azure-na.json='{
    "marketplace_account": "azure-na",
    "auth":
    {
        "AZURE_TENANT_ID": "38bac950-3305-4f71-94a0-3df0bf69590c",
        "AZURE_PUBLISHER_NAME": "publisher-na",
        "AZURE_API_SECRET": "super.secret.na",
        "AZURE_CLIENT_ID":"5d4892f7-769a-4fae-aab3-1f4f5c35b592",
        "AZURE_STORAGE_CONNECTION_STRING": "DefaultEndpointsProtocol=https;AccountName=dummyname;AccountKey=redacted"
    }
}' \
  --from-literal=azure-emea.json='{
    "marketplace_account": "azure-emea",
    "auth":
    {
        "AZURE_TENANT_ID": "38bac950-3305-4f71-94a0-3df0bf69590c",
        "AZURE_PUBLISHER_NAME": "publisher-emea",
        "AZURE_API_SECRET": "super.secret.emea",
        "AZURE_CLIENT_ID":"e726191f-e7db-4611-8906-9beff6c63304",
        "AZURE_STORAGE_CONNECTION_STRING": "DefaultEndpointsProtocol=https;AccountName=dummyname;AccountKey=redacted"
    }
}'
