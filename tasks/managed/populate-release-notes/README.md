# populate-release-notes

Tekton task to populate fields of the releaseNotes  key in the data.json
file. It will update the data.json in place so that downstream tasks relying on
the releaseNotes data can use it.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| dataPath                | Path to the JSON string of the merged data to update                                                                       | No       | -                       |
| snapshotPath            | Path to the JSON string of the mapped Snapshot in the data workspace                                                       | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |
