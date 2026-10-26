# filter-already-released-advisory-rpms

Filters RPMs already published in advisories and reduces the snapshot to only
components that still have RPMs to publish.

This is a **managed Tekton task** that:
- Pulls RPM files from each component's OCI artifact
- Transforms RPM metadata into purls for advisory matching
- Triggers an internal task via InternalRequest to check advisories
- Validates Pulp digests for RPMs in advisories (rebuild detection)
- Keeps all RPMs for each component with at least one RPM missing from advisories
- When signedPulpDomain is set, stops before signing if any retained RPM is already in signed Pulp
  (including partial releases, which need a separate resume path)
- Removes components with an empty `.rpmsToPublish` list
- Overwrites the snapshot file in-place

## Parameters

| Name                     | Description                                                                                                                                                                                                 | Optional | Default value                |
|--------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------|
| snapshotPath             | Path to the JSON Snapshot spec in the data workspace                                                                                                                                                        | No       | -                            |
| dataPath                 | Path to the JSON data file in the data workspace                                                                                                                                                            | No       | -                            |
| releasePlanAdmissionPath | Path to the JSON string of the ReleasePlanAdmission in the data workspace                                                                                                                                   | No       | -                            |
| PULP_DOMAIN              | The domain to use for Pulp operations                                                                                                                                                                       | No       | -                            |
| signedPulpDomain         | When set, stop if an RPM in a component needing an advisory already exists in this signed Pulp domain. Check both published and latest repository versions before a new release attempt can re-sign the RPM | Yes      | ""                           |
| PULP_SECRET_NAME         | The name of the secret containing the Pulp cli.toml file                                                                                                                                                    | No       | -                            |
| DEFAULT_EXCLUDES         | comma-delimited list of file patterns to exclude from consideration                                                                                                                                         | Yes      | -debuginfo-, -debugsource-   |
| DEFAULT_ARCHITECTURES    | Comma-delimited list of arch repos. Noarch RPMs are always checked and published to every repo in this list                                                                                                 | Yes      | x86_64,aarch64,s390x,ppc64le |
| pipelineRunUid           | UID of the current pipelineRun                                                                                                                                                                              | No       | -                            |
| synchronously            | Whether to wait for the InternalRequest completion                                                                                                                                                          | Yes      | true                         |
| ociStorage               | The OCI repository where the Trusted Artifacts are stored                                                                                                                                                   | Yes      | empty                        |
| ociArtifactExpiresAfter  | Expiration date for the trusted artifacts created in the OCI repository                                                                                                                                     | Yes      | 1d                           |
| trustedArtifactsDebug    | Flag to enable debug logging in trusted artifacts                                                                                                                                                           | Yes      | ""                           |
| orasOptions              | oras options to pass to Trusted Artifacts calls                                                                                                                                                             | Yes      | ""                           |
| sourceDataArtifact       | Location of trusted artifacts to be used to populate data directory                                                                                                                                         | Yes      | ""                           |
| dataDir                  | The location where data will be stored                                                                                                                                                                      | Yes      | /var/workdir/release         |
| taskGitUrl               | The url to the git repo where the release-service-catalog tasks to be used                                                                                                                                  | No       | -                            |
| taskGitRevision          | The revision in the taskGitUrl repo to be used                                                                                                                                                              | No       | -                            |
| caTrustConfigMapName     | The name of the ConfigMap to read CA bundle data from                                                                                                                                                       | Yes      | trusted-ca                   |
| caTrustConfigMapKey      | The name of the key in the ConfigMap that contains the CA bundle data                                                                                                                                       | Yes      | ca-bundle.crt                |
