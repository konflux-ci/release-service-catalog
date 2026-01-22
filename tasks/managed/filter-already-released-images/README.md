# filter-already-released-images

Tekton task to filter out images from a snapshot that have already been released.

This task can check one or more release activities before filtering:
1. Registry State (always): Validates ALL required tags exist with correct digest in target registries
2. Pyxis Metadata (optional): Validates ContainerImage entries exist with all tags and RPM Manifest data
3. File Updates (optional): Validates GitLab MRs exist (if spec.data.fileUpdates specified)

Components are only filtered if ALL enabled checks pass. This ensures:
- Mixed snapshots (old + new components) work correctly
- Partial failures can recover on retry
- Complete metadata is verified before filtering

The task overwrites the original snapshot file with a filtered version containing only
components that need to be released.

This task must run AFTER apply-mapping since it needs the mapped target repositories
and their required tags from the enriched snapshot stored in trusted artifacts

## Parameters

| Name                    | Description                                                                                                                                                            | Optional | Default value                                             |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                                                                     | No       | -                                                         |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                              | Yes      | empty                                                     |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire                                             | Yes      | 1d                                                        |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                                 | Yes      | ""                                                        |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                        | Yes      | ""                                                        |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                    | Yes      | ""                                                        |
| dataDir                 | The location where data will be stored                                                                                                                                 | Yes      | /var/workdir/release                                      |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                                  | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                         | No       | -                                                         |
| dataPath                | Path to the JSON string of the merged data in the data workspace Required if checkPyxis=true or checkFileUpdates=true                                                  | Yes      | ""                                                        |
| checkPyxis              | Whether to check Pyxis metadata completion. Set to 'true' to verify ContainerImage entries exist with all tags and RPM Manifest data. Requires pyxisSecret parameter   | Yes      | false                                                     |
| pyxisSecret             | The kubernetes secret for Pyxis authentication (needs keys: cert, key) Required if checkPyxis=true                                                                     | Yes      | pyxis-secret                                              |
| pyxisServer             | The Pyxis server: production, production-internal, stage-internal, or stage Only used if checkPyxis=true                                                               | Yes      | production                                                |
| checkFileUpdates        | Whether to check file updates completion. Set to 'true' to verify GitLab MRs exist Only applies if spec.data.fileUpdates is specified. Requires gitlabSecret parameter | Yes      | false                                                     |
| gitlabSecret            | The kubernetes secret for GitLab API access (needs key: token) Required if checkFileUpdates=true                                                                       | Yes      | gitlab-secret                                             |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                                                                  | Yes      | trusted-ca                                                |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                  | Yes      | ca-bundle.crt                                             |
