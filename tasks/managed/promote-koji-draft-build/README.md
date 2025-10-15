# promote-koji-draft-build

Tekton task to promote draft build in koji instance.

## Parameters

| Name                    | Description                                                                                                                                                                        | Optional | Default value        |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON file of the mapped Snapshot spec in the data workspace                                                                                                            | No       | -                    |
| dataPath                | Path to the JSON file of the merged data to use in the data workspace                                                                                                              | No       | -                    |
| pushSecret              | The secret that is used for login koji instance                                                                                                                                    | No       | -                    |
| pipelineImage           | The image url with koji (1.34 or higher), jq and kinit installed for running the promote-koji-draft-build task, please make sure you have such image or you build this image first | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                                          | Yes      | empty                |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                                | Yes      | ""                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                                         | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                             | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                                    | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                                                                             | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                                              | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                     | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                                                                              | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                              | Yes      | ca-bundle.crt        |
