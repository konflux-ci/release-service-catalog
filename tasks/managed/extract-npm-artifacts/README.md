# extract-npm-artifacts

Extract npm packages from OCI snapshot artifacts for Pulp upload.
Pulls each snapshot component image with oras into a digest-namespaced
directory, populates releaseNotes.content.artifacts from embedded SPDX
pkg:npm PURLs, and fetches Tekton Chains SLSA provenance (hard-fails if
missing, unverifiable, or not trusted). Provenance must match the image
digest and come from Konflux Chains with pipelineRef.name promote-npm or
build-npm and an invocationId in a trusted tenant namespace (default
calunga-tenant). Business logic runs as a single plumbing-utils command
(npm-release-extract); requires at least one .tgz after extract

## Parameters

| Name                        | Description                                                                                                                                                | Optional | Default value        |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------------------|
| SNAPSHOT_PATH               | Path to the snapshot spec file containing image information                                                                                                | No       | -                    |
| sourceDataArtifact          | Trusted Artifact to use to obtain the Snapshot                                                                                                             | No       | -                    |
| dataDir                     | The location where data will be stored                                                                                                                     | Yes      | /var/workdir/content |
| filesDir                    | The relative path within dataDir where files will be extracted                                                                                             | Yes      | files                |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                                                                                  | No       | -                    |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                                                                          | Yes      | 1d                   |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                                                                            | Yes      | ""                   |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                     | Yes      | ""                   |
| trustedProvenanceNamespaces | Comma-separated Kubernetes namespaces allowed to produce accepted Chains provenance. Matched against runDetails.metadata.invocationId as "<namespace>/..." | Yes      | calunga-tenant       |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                      | No       | -                    |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                                                                             | No       | -                    |
| dataPath                    | Path to data.json relative to dataDir                                                                                                                      | No       | -                    |
