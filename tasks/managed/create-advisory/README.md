# create-advisory

Tekton task to create an advisory via an InternalRequest. The advisory data is pulled from the data JSON. The origin
workspace from the ReleasePlanAdmission and Application from the Snapshot are also used. The advisory is created in
a GitLab repository. Which repository to use is determined by the contents on the mapped repositories.
Only all `redhat-pending` or all `redhat-prod` repositories may be specified in `.data.mapping`

## Parameters

| Name                     | Description                                                                                                                | Optional | Default value                                            |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------------------------------------------|
| jsonKey                  | The json key containing the advisory data                                                                                  | Yes      | .releaseNotes                                            |
| releasePlanAdmissionPath | Path to the JSON string of the ReleasePlanAdmission in the data workspace                                                  | No       | -                                                        |
| snapshotPath             | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                                                        |
| dataPath                 | Path to the data JSON in the data workspace                                                                                | No       | -                                                        |
| environment              | The environment for the advisory to be published. Options are stage and production                                         | Yes      | ""                                                       |
| resultsDirPath           | Path to the results directory in the data workspace                                                                        | No       | -                                                        |
| request                  | Type of request to be created                                                                                              | Yes      | create-advisory                                          |
| synchronously            | Whether the task should wait for InternalRequests to complete                                                              | Yes      | true                                                     |
| pipelineRunUid           | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                                                        |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                    |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                       |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                       |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                       |
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                       |
| dataDir                  | The location where data will be stored                                                                                     | Yes      | /var/workdir/release                                     |
| cgwHostname              | The hostname of the content-gateway to publish the metadata to                                                             | Yes      | https://developers.redhat.com/content-gateway/rest/admin |
| cgwSecret                | The kubernetes secret to use to authenticate to content-gateway. It needs to contain two keys: username and token          | Yes      | publish-to-cgw-secret                                    |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                                                        |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                                                             | No       | -                                                        |
| caTrustConfigMapName     | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca                                               |
| caTrustConfigMapKey      | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt                                            |
