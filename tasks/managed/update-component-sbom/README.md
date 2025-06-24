# update-component-sbom

Tekton task to update component-level SBOMs with purls containing release-time info.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| sbomPath                | Path in the data directory to store the updated SBOMs to                                                                   | Yes      | sboms                   |
| snapshotSpec            | Path to the mapped snapshot spec                                                                                           | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| subdirectory            | Subdirectory inside the workspace to be used                                                                               | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |
