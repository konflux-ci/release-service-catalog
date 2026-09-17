# push-py-osv-pulp

Publish generated Python OSV security-metadata files to a dedicated Pulp
file repository. Restores the trusted artifact produced by generate-py-osv
(or push-py-pulp) and uploads each JSON file under securityMetadataDir to
PULP_FILE_REPOSITORY using the pulp CLI. This is a sibling of push-py-pulp
(upload-py-pulp): the wheels go to a Python package repository, the OSV
files go to a separate Pulp file repository.

## Parameters

| Name                        | Description                                                                                           | Optional | Default value                |
|-----------------------------|-------------------------------------------------------------------------------------------------------|----------|------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | The name of the secret containing the terms-based registry service account credentials                | Yes      | rhtl-pulp-credentials-secret |
| PULP_URL                    | The base URL of the Pulp server                                                                       | No       | -                            |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                 | No       | -                            |
| PULP_FILE_REPOSITORY        | The Pulp file repository to publish OSV security metadata to                                          | No       | -                            |
| securityMetadataDir         | The relative path within dataDir where OSV security metadata files are located                        | Yes      | security_metadata            |
| sourceDataArtifact          | Trusted Artifact containing the generated OSV security metadata files                                 | No       | -                            |
| dataDir                     | The location where data will be stored                                                                | Yes      | /var/workdir                 |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                           |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                           |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                           |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                            |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                        | No       | -                            |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                             | No       | -                            |
