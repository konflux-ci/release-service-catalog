# marketplacesvm-push-disk-images

Tekton Task to publish VM disk images into various cloud marketplaces using `pubtools-marketplacesvm`.

It currently supports images in `raw` and `vhd` formats for `AWS` and `Azure` respectively.

## Parameters

| Name                    | Description                                                                                                                                          | Optional | Default value |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|----------|---------------|
| snapshotPath            | Path to the JSON string of the mapped snapshot spec in the data workspace. It must be processed by the "apply-mapping" task first                    | No       | -             |
| cloudMarketplacesSecret | Env specific secret containing the marketplaces credentials                                                                                          | No       | -             |
| prePush                 | Whether perform a pre-push (true) or not (false). When true it will not publish PROD                                                                 | Yes      | false         |
| concurrentLimit         | The maximum number of images to be pulled at once                                                                                                    | Yes      | 3             |
| uploadContainerName     | The name of the container to upload the images to                                                                                                    | Yes      | konfluxupload |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                            | No       | -             |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire. The format is YYYY-MM-DD | Yes      | ""            |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                      | Yes      | ""            |
| sourceDataArtifact      | The Trusted Artifact URI pointing to the artifact with the application snapshot spec and the release data                                            | No       | -             |
| dataDir                 | The location where data will be stored                                                                                                               | No       | -             |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                               | Yes      | ""            |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                | No       | -             |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                       | No       | -             |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                                                | Yes      | trusted-ca    |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                                                | Yes      | ca-bundle.crt |
