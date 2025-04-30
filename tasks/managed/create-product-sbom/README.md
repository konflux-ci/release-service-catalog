# create-product-sbom

Tekton task to create a product-level SBOM to be uploaded to Atlas from
releaseNotes content.

## Parameters

| Name                    | Description                                                                                                                | Optional | Default value           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------|
| sbomPath                | Path in the data directory to store the created SBOM to                                                                    | Yes      | sboms                   |
| dataPath                | Path to the data file from collect-data                                                                                    | No       |                         |
| snapshotSpec            | Path to the mapped snapshot spec                                                                                           | No       | -                       |
| ociStorage              | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                   |
| ociArtifactExpiresAfter | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                      |
| trustedArtifactsDebug   | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                      |
| orasOptions             | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                      |
| sourceDataArtifact      | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                      |
| dataDir                 | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path) |
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                      |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                      |

## Changes in 2.0.0
* Task was refactored to use the new SBOM workflow. SBOMs are now generated from the mapped snapshot spec.
  * Renamed `productSBOMPath` result to `sbomPath` and param `dataJsonPath` to `dataPath`.
  * Added optional `sbomPath` param specifying the path to store the created SBOM to.
  * Added `snapshotSpec` param specifying the path to the mapped snapshot spec.
  * Fixed executable to run script as module.

## Changes in 1.0.0
* This task now supports Trusted artifacts

## Changes in 0.2.1
* Fixed component-product relationship in SBOM.

## Changes in 0.2.0
* Output directory path instead of a file path.

## Changes in 0.1.1
* The release-service-utils image was updated to include a fix when generating name of product level SBOM - it should be based on "{product name} {product version}"
