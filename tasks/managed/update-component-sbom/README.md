# update-component-sbom

Tekton task to update component-level SBOMs with purls containing release-time info.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| sbomPath                | Path in the data directory to store the updated SBOMs to                                                                   | Yes      | sboms                   |
| snapshotSpec            | Path to the mapped snapshot spec                                                                                           | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| subdirectory            | Subdirectory inside the workspace to be used                                                                               | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 2.1.0
* Added compute resource limits

## Changes in 2.0.2
* Limited concurrency to 8 SBOM updates

## Changes in 2.0.1
* Fixed silent script failures
* Fixed cosign authentication issue

## Changes in 2.0.0
* Refactored task to use the new SBOM generation workflow. SBOMs are now
  generated from mapped snapshot specs.
  * Removed `sbomJsonPath`, `downloadedSbomPath` params. This task is no longer
   dependent on sbom data from `populate-release-notes-images` and build-time
  * Added optional `sbomPath` param specifying the path to store updated SBOMs to.
  * Added `snapshotSpec` param specifying the path to the mapped snapshot spec.
   SBOMs from `push-rpm-data-to-pyxis`.
  * Fixed executable to run script as module.

## Changes in 1.0.0
* This task now supports Trusted artifacts

## Changes in 0.2.0
- Rename dataPath parameter to sbomJsonPath to better reflect usage

## Changes in 0.1.1
- (ISV-5321) Set a `name` of SPDX document to external reference of the component. The name is set to external image pullspec given by the public registry + repository + digest. Example: registry.redhat.io/ubi8/ubi-minimal@sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef.
