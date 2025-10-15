# publish-pyxis-repository

Tekton task to mark all repositories in the mapped snapshot as published in Pyxis.
This is currently only meant to be used in the rh-push-to-registry-redhat-io
and rh-advisories pipelines,
so it will convert the values to the ones used for registry.redhat.io releases.
E.g. repository "quay.io/redhat-prod/my-product----my-image" will be converted to use
registry "registry.access.redhat.com" and repository "my-product/my-image" to identify
the right Container Registry object in Pyxis. The task also optionally
marks the repositories as source_container_image_enabled true if pushSourceContainer
is true in the data JSON.
Additionally, this task respects the `publish-on-push` flag. If `false`, then the task
does not publish the repository.

The task emits a result: `signRegistryAccessPath`

This contains the relative path in the workspace to a text file that contains a list of repositories
that needs registry.access.redhat.com image references to be signed (i.e.
requires_terms=true), one repository string per line, e.g. "rhtas/cosign-rhel9".

Note: This task runs quite early on in the pipeline, because we need the result it produces
for the signing tasks (and `rh-sign-image` runs quite early to begin with). So this means
that if you're releasing to a repo for the first time, the repository might get published
even before the actual image is pushed and published. But we checked with RHEC team and this
shouldn't cause any problems, because RHEC will ignore repos with no published images.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value        |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| server                  | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'                         | Yes      | production           |
| pyxisSecret             | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert                          | No       | -                    |
| snapshotPath            | Path to the JSON file containing the mapped Snapshot spec in the data workspace                                            | No       | -                    |
| dataPath                | Path to the JSON string of the merged data to use in the data workspace                                                    | No       | -                    |
| resultsDirPath          | Path to the results directory in the data workspace                                                                        | No       | -                    |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                   |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                   |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                   |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                   |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | /var/workdir/release |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | -                    |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | -                    |
| caTrustConfigMapName    | The name of the ConfigMap to read CA bundle data from                                                                      | Yes      | trusted-ca           |
| caTrustConfigMapKey     | The name of the key in the ConfigMap that contains the CA bundle data                                                      | Yes      | ca-bundle.crt        |
