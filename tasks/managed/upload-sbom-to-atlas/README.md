# upload-sbom-to-atlas
This Tekton task gathers SBOM data from a directory specified by the parameters
and uploads them to Atlas. Supports both CycloneDX and SPDX format. If the push 
to Atlas fails, the SBOM is pushed to an S3 bucket. The push to Atlas is then 
retried asynchronously from the bucket by another service.

The provided directory is searched for SBOMs recursively and all found SBOMs
are uploaded as-is to Atlas.

## Parameters
| Name                      | Description                                                                                                                | Optional | Default value                                                                 |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------- |
| sbomDir                   | Directory containing SBOM files relative to the data workspace.                                                            | No       | None                                                                          |
| httpRetries               | Max HTTP retry count.                                                                                                      | Yes      | 3                                                                             |
| atlasSecretName           | Name of the Secret containing SSO auth credentials for Atlas.                                                              | Yes      | atlas-prod-sso-secret                                                         |
| ATLAS_API_URL             | URL of the Atlas API host.                                                                                                 | Yes      | https://atlas.release.devshift.net                                            |
| ssoTokenUrl               | URL of the SSO token issuer.                                                                                               | Yes      | https://auth.redhat.com/auth/realms/EmployeeIDP/protocol/openid-connect/token |
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
