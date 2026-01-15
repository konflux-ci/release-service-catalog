# filter-already-released-by-pyxis-and-file-updates

Tekton task to filter out images from a snapshot that have already been released.
This task verifies:
- Pyxis metadata (always required)
- fileUpdates completion (only when `.fileUpdates` is configured in the merged data file)

The fileUpdates completion check is performed via an InternalRequest (internal GitLab access),
not by calling GitLab directly from this managed task.

The task overwrites the original snapshot file in place with a filtered version
containing only components that still need release work.

This task expects a mapped snapshot (repositories/tags already resolved) from
trusted artifacts.

Fail-safe behavior: The task fails only if Pyxis credentials are missing or
pyxisServer is invalid. For all other issues (API errors, missing data, internal
check errors), components are kept and the pipeline proceeds.

## Parameters

| Name                    | Description                                                                                                                                                       | Optional | Default value                                             |
|-------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                                                                | No       | -                                                         |
| dataPath                | Path to the JSON string of the merged data in the data workspace                                                                                                  | Yes      | ""                                                        |
| request                 | Name of the internal pipeline used to check fileUpdates completion                                                                                                | Yes      | check-file-updates                                        |
| requestTimeout          | InternalRequest timeout (seconds) for the fileUpdates completion check                                                                                            | Yes      | 300                                                       |
| synchronously           | Whether to run internal requests synchronously or not                                                                                                             | Yes      | true                                                      |
| pipelineRunUid          | The uid of the current PipelineRun. Used as a label value when creating internal requests                                                                         | No       | -                                                         |
| pyxisSecret             | The kubernetes secret for Pyxis authentication (needs keys: cert, key)                                                                                            | Yes      | pyxis-secret                                              |
| pyxisServer             | The Pyxis server: production, production-internal, stage-internal, or stage                                                                                       | Yes      | production                                                |
| apiRetryCount           | Number of retries for API calls to Pyxis                                                                                                                          | Yes      | 3                                                         |
| apiConnectTimeout       | Connection timeout in seconds for API calls to Pyxis                                                                                                              | Yes      | 10                                                        |
| apiMaxTime              | Maximum time in seconds for API calls to Pyxis                                                                                                                    | Yes      | 30                                                        |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                                                             | Yes      | trusted-ca                                                |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                                                             | Yes      | ca-bundle.crt                                             |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored. Must be provided by the pipeline (e.g., quay.io/redhat-user-workloads/workspace/application/component) | Yes      | ""                                                        |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                        | Yes      | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                            | Yes      | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                   | Yes      | ""                                                        |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                               | Yes      | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                                                            | Yes      | /var/workdir/release                                      |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                             | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                    | No       | -                                                         |
