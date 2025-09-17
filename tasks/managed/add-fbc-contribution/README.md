# add-fbc-contribution

Task to create an internalrequest to add fbc contributions to index images

## Parameters

| Name                        | Description                                                                                                                | Optional | Default value        |
|-----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath                | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                    |
| dataPath                    | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| fromIndex                   | fromIndex value updated by update-ocp-tag task                                                                             | No       | -                    |
| pipelineRunUid              | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                    |
| ocpVersion                  | The OCP version for all components in this release                                                                         | No       | -                    |
| resultsDirPath              | Path to the results directory in the data workspace                                                                        | No       | -                    |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact          | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                     | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| maxBatchSize                | Maximum number of FBC fragments to process in a single batch                                                               | Yes      | 5                    |
| mustPublishIndexImage       | Whether the index image should be published (from prepare-fbc-parameters)                                                  | No       | -                    |
| mustOverwriteFromIndexImage | Whether to overwrite the from index image (from prepare-fbc-parameters)                                                    | No       | -                    |
| iibServiceAccountSecret     | IIB service account secret name (from prepare-fbc-parameters)                                                              | No       | -                    |
| resolvedTargetIndex         | Resolved target index with sanitized tag (from prepare-fbc-parameters)                                                     | No       | -                    |
| maxRetries                  | Maximum number of retry attempts for failed internal requests                                                              | Yes      | 3                    |
| batchRetryDelaySeconds      | Delay between batch retry attempts in seconds                                                                              | Yes      | 60                   |
