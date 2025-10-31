# filter-published-fbc-images

Filters snapshot to remove already-released FBC fragments by querying Pyxis index images.
Queries for index images and checks if fragments are present in their bundles/related_images fields.
Components already published are filtered out to prevent EC validation failures.

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
