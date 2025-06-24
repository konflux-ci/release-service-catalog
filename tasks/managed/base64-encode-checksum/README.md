# base64-encode-checksum

Task to encode the Terraform Checksum file.

It returns as a result the blob to sign, that is the result of the base64 encoded checksum

## Parameters

| Name                    | Description                                                                                                                | Optional  | Default value            |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------|
| binaries_dir            | Path inside the image where the binaries to extract are stored                                                             | Yes       | "binaries"               |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes       | empty                    |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes       | 1d                       |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes       | ""                       |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes       | ""                       |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes       | ""                       |
| dataDir                 | The location where data will be stored                                                                                     | Yes       | $(workspaces.data.path)  |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No        | ""                       |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No        | ""                       |
