# upload-py-pulp

Upload Python packages (with attestations) to a Pulp repository.

## Parameters

| Name                        | Description                                                                                           | Optional | Default value                |
|-----------------------------|-------------------------------------------------------------------------------------------------------|----------|------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | The name of the secret containing the terms-based registry service account credentials                | Yes      | rhtl-pulp-credentials-secret |
| PULP_BASE_URL               | The base URL of the Pulp server                                                                       | No       | -                            |
| PULP_API_ROOT               | The API root path of the Pulp server                                                                  | Yes      | /api/                        |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                 | No       | -                            |
| PULP_REPOSITORY             | The Pulp repository to upload to                                                                      | No       | -                            |
| sourceDataArtifact          | Trusted Artifact containing the signed wheels and attestations                                        | No       | -                            |
| dataDir                     | The location where data will be stored                                                                | Yes      | /var/workdir                 |
| filesDir                    | The relative path within dataDir where wheel files are located                                        | Yes      | files                        |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                           |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                           |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                           |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                            |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                        | No       | -                            |
