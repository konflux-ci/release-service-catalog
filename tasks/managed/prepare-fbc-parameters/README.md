# prepare-fbc-parameters

Task to prepare FBC parameters from all fragments with comprehensive validation.

Includes package validation, version consistency checking, opt-in status collection,
and strategy-aware publishing decisions (hotfix, staging, etc.).

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                    |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| pyxisSecret             | Name of secret which contains the required credentials for authentication to pyxis                                         | No       | -                    |
| pyxisServer             | Pyxis server to use                                                                                                        | Yes      | production           |
| maxRetries              | Maximum number of retry attempts for failed internal requests                                                              | Yes      | 3                    |
| retryDelaySeconds       | Delay between retry attempts in seconds                                                                                    | Yes      | 30                   |
| pipelineRunUid          | The uid of the current pipelineRun. It is only available at the pipeline level                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
