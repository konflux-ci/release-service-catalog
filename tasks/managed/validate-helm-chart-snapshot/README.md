# validate-helm-chart-snapshot

Validates that each component in the mapped snapshot is a Helm OCI artifact and that release tags and
destination repository names match chart metadata from the OCI manifest (annotations). Compares
org.opencontainers.image.version to each repository tag using Helm's OCI convention (first underscore in a
tag corresponds to SemVer build-metadata plus). Compares org.opencontainers.image.title to the basename of
each mapped repository URL (path after converting ---- to /).

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the mapped Snapshot spec in the data workspace                                                  | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions are stored                                 | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
