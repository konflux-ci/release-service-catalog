# update-trusted-tasks

Tekton task to update trusted-tasks list OCI artifact.
Once a task is released as a bundle, the list of trusted-tasks should be
updated with the new task.
The OCI artifact containing the trusted-tasks list is named `acceptable-data-bundles` and should reside in the same
org in the registry. If it is already in place, it will be used as an input to which the results will be appended,
else a new artifact will be created.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| sourceDataArtifact      | The source data artifact to use for trusted artifacts                                                                      | Yes      | ""                   |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| registrySecret          | The name of the secret with the registry token for making repositories public                                              | Yes      | registry-token       |
