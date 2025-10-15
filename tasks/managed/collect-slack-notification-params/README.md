# collect-slack-notification-params

Tekton task that collects slack configuration options from Release CRs and the data file. A formatted message is
emitted as a task result for downstream tasks to use.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value                                                      |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|--------------------------------------------------------------------|
| releasePath             | Path to the JSON string of the Release CR                                                                                  | No       | -                                                                  |
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                                                                  |
| dataPath                | Path to the JSON string of the merged data containing the configuration options to use                                     | No       | -                                                                  |
| hacUrl                  | Root URL of HAC UI (hybrid access console)                                                                                 | Yes      | https://console.redhat.com/preview/application-pipeline/workspaces |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                              |
| sourceDataArtifact      | The source data artifact from the previous task                                                                            | Yes      | ""                                                                 |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                                 |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                                 |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                                 |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                               |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                                  |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                                  |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                                         |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                                      |
