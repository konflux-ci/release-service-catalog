# run-file-udpates

Tekton task to create InternalRequests for each repository that needs to be updated. This information is extracted from
the field `spec.data.fileUpdates` in the ReleasePlanAdmission resource.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value            |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|--------------------------|
| jsonKey                 | JSON key where the information is defined                                                                                  | Yes      | .spec.data.fileUpdates[] |
| fileUpdatesPath         | Path to the JSON file containing the key                                                                                   | No       | -                        |
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                        |
| request                 | Type of request to be created                                                                                              | Yes      | file-updates             |
| synchronously           | Whether the task should wait for InternalRequests to complete                                                              | Yes      | true                     |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                        |
| resultsDirPath          | Path to results directory in the data workspace                                                                            | No       | -                        |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                    |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                       |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                       |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                       | 
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                       |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path)  |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                       |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                       |
