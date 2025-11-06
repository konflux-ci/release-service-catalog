# filter-already-released-images

Tekton task to filter out images from a snapshot that have already been released.
This task checks target registries to determine if push-snapshot has completed successfully
for each component by validating that ALL required tags exist with the correct digest.
Components that are fully released (all tags present) are filtered out before conforma validation.

Tag-level validation ensures complete releases and prevents filtering components with 
partial tag pushes. A component is only filtered if ALL repositories have ALL
required tags pointing to the correct digest.

The task overwrites the original snapshot file in place with a filtered version 
containing only unpublished or partially published images.

This task must run AFTER apply-mapping since it needs the mapped target repositories
and their required tags from the enriched snapshot stored in trusted artifacts

## Parameters

| Name                    | Description                                                                                                                 | Optional | Default value                                             |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                          | No       | -                                                         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                   | Yes      | empty                                                     |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository.  An empty string means the artifacts do not expire | Yes      | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                      | Yes      | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                             | Yes      | ""                                                        |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                         | Yes      | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                      | Yes      | /var/workdir/release                                      |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                       | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                              | No       | -                                                         |
