# push-sbom-to-s3
If pushing the SBOM to Atlas failed, this task pushes it to an S3 bucket, from
which the push will be retried once Atlas is available.

## Parameters

| Name               | Description                                   | Optional | Default value |
|:------------------:|:---------------------------------------------:|:--------:|:-------------:|
| retryAwsSecretName | Name of the k8s secret containing AWS secrets | No       |               |
| retryS3Bucket      | Name of the S3 bucket to push to              | No       |               |
| sbomPath           | Full path to the SBOM to be pushed to S3      | No       |               |
