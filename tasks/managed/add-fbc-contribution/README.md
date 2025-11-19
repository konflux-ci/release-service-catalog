# add-fbc-contribution

Task to create internalrequests to add fbc contributions to index images. It can batch
multiple fragments into a single IIB request and can also split requests according
to their OCP versions.

This task batches FBC fragments to submit them to IIB in sets of params.maxBatchSize.
The Snapshot has been previously augmented by prepare-fbc-snapshot to include OCP and
target index metadata for each component.

In this task, we split fragments up by their OCP versions and then process each of these
in parallel. Multiple OCP version groups are processed simultaneously, as IIB is capable
of handling updates to index images for different OCP versions in parallel (but only one
request at a time for a given version). For each OCP version, we chain together batches so that
the final targetIndex produced will have all fragments added. This means that the index_image
from one internal request will be set as the fromIndex for the next request within that OCP
version. This parallel approach significantly reduces FBC release duration, as the total time
is only as long as the slowest IIB run rather than the sum of all IIB run durations.

Since we have seen flakiness in IIB requests in the past, we retry and failed batches
and internal requests can attach onto currently in progress IIB requests. We retry batches
at the end to allow for timed out requests to finish so that we can just get the final
result. This will slightly compress the time in which batches are entered into the IIB
queue to reduce the effect of a full queue on a single release.

## Parameters

| Name                        | Description                                                                                                                | Optional | Default value        |
|-----------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath                | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                    |
| dataPath                    | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| pipelineRunUid              | The uid of the current pipelineRun. Used as a label value when creating internal requests                                  | No       | -                    |
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
| maxRetries                  | Maximum number of retry attempts for failed internal requests                                                              | Yes      | 3                    |
| batchRetryDelaySeconds      | Delay between batch retry attempts in seconds                                                                              | Yes      | 60                   |
| caTrustConfigMapName        | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey         | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
| overrideMemoryLimitMi       | Override memory limit for testing adaptive calculation (empty = auto-detect from cgroups)                                  | Yes      | ""                   |
