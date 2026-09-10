# filter-published-fbc-images

Filters snapshot to remove already-released FBC fragments by querying Pyxis index images.
Queries for index images and checks if fragments are present in their bundles/related_images fields.
Components already published are filtered out to prevent EC validation failures.
Extracts and attaches ocpVersion field to each component for downstream tasks.
OCP version resolution order:
  1. com.redhat.fbc.openshift.version label - expects a non-empty JSON array.
     Currently only the first OCP version from the array is used.
     Recommended for binaryless fragments. Works for pre-GA OCP versions.
     Enables shipping a single FBC to multiple OCP catalogs. Allowed versions for this label are >=v4.15
     Dockerfile example: LABEL com.redhat.fbc.openshift.version='["v4.18","v4.21"]'
  2. org.opencontainers.image.base.name annotation - Legacy fallback.
     Requires OCP-version-specific operator-registry image. Cannot target pre-GA versions.

## Parameters

| Name                    | Description                                                                                        | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                 | No       | -                    |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                            | No       | -                    |
| pyxisSecret             | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys - cert and key | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                          | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository                            | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts                                                  | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                    | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                             | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored              | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                     | No       | -                    |
