# check-labels

Tekton task to ensure that components destination repositories names and cpes match the supplied image labels.
With enforce parameter set to false, the task will just output warnings whenever the values don't match.

## Parameters

| Name                    | Description                                                                                                                                                                                                               | Optional | Default value        |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                                                                                                                   | No       | -                    |
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                                                                                                                 | No       | -                    |
| enforce                 | If set to true, validation failures will be logged as errors, causing the task to fail. If set to false (the default), validation failures will be logged as warnings instead, allowing the task to complete successfully | Yes      | false                |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                                 | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                                                                                | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                                                                    | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                                                                           | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                                                                       | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                                                                                                                    | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                                                                                     | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                                                            | No       | -                    |
