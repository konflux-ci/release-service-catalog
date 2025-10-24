# set-advisory-severity

Tekton task to set the severity level in the releaseNotes key of the data.json. It will use an InternalRequest to query OSIDB for each CVE present. If the type is not RHSA, no action will be performed. This check is only performed for images and not for generic artifact types like binaries or disk images.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| requestTimeout          | InternalRequest timeout                                                                                                    | Yes      | 7200                 |
| pipelineRunUid          | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
