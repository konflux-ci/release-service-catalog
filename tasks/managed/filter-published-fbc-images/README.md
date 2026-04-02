# filter-published-fbc-images

Filters already-published FBC fragments from the Snapshot before release.
Queries previous Release CRs in the tenant namespace (identified via releaseName)
to find FBC fragments that were already successfully published to the same target
index. Components whose fbc_fragment digest matches a previously-released artifact
are removed; all others are kept. Also attaches ocpVersion to every remaining
component for downstream tasks. If the Release CR lookup fails or releaseName is
not provided, all components are kept (safe fallback).

## Parameters

| Name                    | Description                                                                                                                                                                                                                     | Optional | Default value        |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| snapshotPath            | Path to the JSON string of the Snapshot spec in the data workspace                                                                                                                                                              | No       | -                    |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                                                                                                                         | No       | -                    |
| releaseName             | The namespaced name (namespace/name) of the current Release CR. Used to look up previously completed releases for the same application to identify already- published FBC fragments. If empty, idempotence filtering is skipped | Yes      | ""                   |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                                       | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository                                                                                                                                                         | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts                                                                                                                                                                               | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                                                                                                                                 | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                                                                                                                             | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                                                                                                                          | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                                                                                           | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                                                                  | No       | -                    |
