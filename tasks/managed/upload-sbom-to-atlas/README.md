# upload-sbom-to-atlas
This Tekton task gathers SBOM data from a directory specified by the parameters,
converting it to a supported version if needed and uploading it to Atlas.
Supports both CycloneDX and SPDX format. If the push to Atlas fails, the SBOM is
pushed to an S3 bucket. The push to Atlas is then retried asynchronously from
the bucket by another service.

The provided directory is searched for SBOMs recursively.

If the SBOMs use a higher version than specified in parameters, `syft convert`
is used to convert them to a supported version. If they are maximum version or
lower, they are uploaded as-is.

## Parameters
| Name                      | Description                                                                                                                | Optional | Default value                                                                 |
|---------------------------|----------------------------------------------------------------------------------------------------------------------------|----------|-------------------------------------------------------------------------------|
| sbomDir                   | Directory containing SBOM files relative to the data workspace.                                                            | No       | None                                                                          |
| httpRetries               | Max HTTP retry count.                                                                                                      | Yes      | 3                                                                             |
| atlasSecretName           | Name of the Secret containing SSO auth credentials for Atlas.                                                              | Yes      | atlas-prod-sso-secret                                                         |
| bombasticApiUrl           | URL of the BOMbastic API host of Atlas.                                                                                    | Yes      | https://sbom.atlas.devshift.net                                               |
| ssoTokenUrl               | URL of the SSO token issuer.                                                                                               | Yes      | https://auth.redhat.com/auth/realms/EmployeeIDP/protocol/openid-connect/token |
| supportedCycloneDxVersion | Maximum supported CycloneDX version.                                                                                       | Yes      | 1.4                                                                           |
| supportedSpdxVersion      | Maximum supported SPDX version.                                                                                            | Yes      | 2.3                                                                           |
| retryAWSSecretName        | Name of the Secret containg auth for AWS.                                                                                  | No       |                                                                               |
| retryS3Bucket             | Name of the S3 bucket to push failed SBOMs to.                                                                             | No       |                                                                               |
| ociStorage                | The OCI repository where the Trusted Artifacts are stored                                                                  | Yes      | empty                                                                         |
| ociArtifactExpiresAfter   | Expiration date for the trusted artifacts created in the OCI repository. An empty string means the artifacts do not expire | Yes      | 1d                                                                            |
| trustedArtifactsDebug     | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                     | Yes      | ""                                                                            |
| orasOptions               | oras options to pass to Trusted Artifacts calls                                                                            | Yes      | ""                                                                            |
| sourceDataArtifact        | Location of trusted artifacts to be used to populate data directory                                                        | Yes      | ""                                                                            |
| subdirectory              | Subdirectory inside the workspace to be used                                                                               | Yes      | ""                                                                            |
| dataDir                   | The location where data will be stored                                                                                     | Yes      | $(workspaces.data.path)                                                       |
| taskGitUrl                | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                      | No       | ""                                                                            |
| taskGitRevision           | The revision in the taskGitUrl repo to be used                                                                             | No       | ""                                                                            |

## Changes in 2.0.0
* Add a step that pushes SBOMs to S3 if they failed to be pushed to Atlas.
* Add non-optional parameters to facilitate the S3 push.

## Changes in 1.0.0
* This task now supports Trusted artifacts

## Changes in 0.2.1
* Ignore error (but output a message) if upload request to Atlas fails.

## Changes in 0.2.0
* Remove option to skip uploading SBOMs. Skipping will be handled via Tekton.
* Rename productSBOMPath parameter to sbomDir. Use SBOM file names as Atlas IDs.
