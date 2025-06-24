# Filter Already Released Advisory Images

This task filters out images from a snapshot that have already been published in advisories.
It is a **managed Tekton task** that triggers an **internal task** using an InternalRequest,
and overwrites the mapped snapshot file with a filtered version containing only **unpublished images**.

The task also outputs a `skip_release` result, which is set to `true`
if all components are already released (and the pipeline can be skipped), or `false` otherwise.

The task overwrites the original mapped snapshot file in place with a filtered version containing only unpublished images. Downstream tasks continue to use the same snapshot path.

## Parameters

| Name                     | Description                                                                                                                | Optional  | Default value                                  |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------|-----------|------------------------------------------------|
| snapshotPath             | Path to the JSON file of the Snapshot spec in the workspace                                                                | No        | -                                              |
| releasePlanAdmissionPath | Path to the JSON file of the ReleasePlanAdmission in the workspace                                                         | No        | -                                              |
| resultsDirPath           | Path to the results directory within the workspace                                                                         | No        | -                                              |
| synchronously            | Whether the task should wait for the InternalRequest to complete                                                           | Yes       | true                                           |
| pipelineRunUid           | UID of the current pipelineRun, used as a label on the InternalRequest                                                     | No        | -                                              |
| taskGitUrl               | Git URL of the release-service-catalog containing internal task logic                                                      | No        | -                                              |
| taskGitRevision          | Git revision or branch name used to run the internal task                                                                  | No        | -                                              |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                  | No        | -                                              |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes       | 1d                                             |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes       | ""                                             |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                            | Yes       | ""                                             |
| sourceDataArtifact       | Location of trusted artifacts used to populate the data directory                                                          | Yes       | ""                                             |
| dataDir                  | The location where data will be stored                                                                                     | No        | $(workspaces.data.path)                        |
| subdirectory             | Subdirectory inside the workspace to be used                                                                               | Yes       | ""                                             |
