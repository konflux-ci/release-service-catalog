# run-file-updates

Tekton task to create InternalRequests for each repository that needs to be updated. This information is extracted
from the field `spec.data.fileUpdates` in the ReleasePlanAdmission resource.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value          |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|------------------------|
| jsonKey                 | The json key containing the file updates                                                                                   | Yes      | .spec.data.fileUpdates |
| fileUpdatesPath         | The path to the file containing the file updates                                                                           | No       | -                      |
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                      |
| request                 | Name of the request                                                                                                        | Yes      | process-file-updates   |
| requestTimeout          | InternalRequest timeout                                                                                                    | Yes      | 900                    |
| synchronously           | Whether to run synchronously or not                                                                                        | Yes      | true                   |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                      |
| resultsDirPath          | Path to the results directory in the data workspace                                                                        | No       | -                      |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                  |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                     |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                     |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                     |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                     |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release   |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                      |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca             |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt          |
