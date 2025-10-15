# filter-already-released-advisory-images

This task filters out images from a snapshot that have already been published
in advisories. It is a **managed Tekton task** that triggers an **internal task**
using an InternalRequest, and overwrites the mapped snapshot file with a
filtered version containing only **unpublished images**.

The task also outputs a `skip_release` result, which is set to `true`
if all components are already released (and the pipeline can be skipped),
or `false` otherwise.

The task overwrites the original mapped snapshot file in place with a
filtered version containing only unpublished images.
Downstream tasks continue to use the same snapshot path.

## Parameters

| Name                     | Description                                                                                                                | Optional | Default value        |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath             | Path to the JSON string of the Snapshot spec in the data workspace                                                         | No       | -                    |
| releasePlanAdmissionPath | Path to the JSON string of the ReleasePlanAdmission in the data workspace                                                  | No       | -                    |
| resultsDirPath           | Path to the results directory in the data workspace                                                                        | No       | -                    |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                  | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision          | Git revision to use for internal task                                                                                      | No       | -                    |
| pipelineRunUid           | UID of the current pipelineRun                                                                                             | No       | -                    |
| synchronously            | Whether to wait for the InternalRequest completion                                                                         | Yes      | true                 |
| dataPath                 | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| caTrustConfigMapName     | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey      | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
