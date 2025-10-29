# push-oot-kmods-to-s3

Task to upload out-of-tree kernel modules to an S3 bucket

## Parameters

| Name                  | Description                                                                            | Optional | Default value                                             |
|-----------------------|----------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| signedKmodsPath       | Path where the kernel modules are stored relative to the dataDir                       | No       | -                                                         |
| dataDir               | The absolute path to the working directory                                             | Yes      | /var/workdir/release                                      |
| s3Endpoint            | The S3 endpoint URL                                                                    | No       | -                                                         |
| s3Bucket              | The name of the destination S3 bucket                                                  | No       | -                                                         |
| s3CredentialsSecret   | The name of the Kubernetes secret containing S3 credentials                            | No       | -                                                         |
| sourceDataArtifact    | Location of trusted artifacts to be used to populate data directory                    | Yes      | ""                                                        |
| orasOptions           | oras options to pass to Trusted Artifacts calls                                        | Yes      | ""                                                        |
| trustedArtifactsDebug | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable | Yes      | ""                                                        |
| taskGitUrl            | The git repository URL for task and StepAction resolution                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision       | The git revision for task and StepAction resolution                                    | Yes      | main                                                      |
