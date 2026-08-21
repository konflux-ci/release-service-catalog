# upload-npm-closure

Publish TL npm closure metadata after Pulp upload: for each assess
*.tl-compliance.json sidecar under FILES_DIR, push per-package compliance
OCI and update the global closure index on Quay (calunga-npm-registry-main).
Quay refs are fixed for calunga-tenant; COMPLIANCE_IMAGE_PREFIX and
CLOSURE_INDEX_IMAGE are set in stepTemplate env. Requires Pulp
credentials (same secret as upload-npm-pulp). Business logic runs as a
single plumbing-utils command (npm-release-closure-update).

## Parameters

| Name                        | Description                                                                                           | Optional | Default value                |
|-----------------------------|-------------------------------------------------------------------------------------------------------|----------|------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | Secret with Pulp username/password keys (same as upload-npm-pulp)                                     | Yes      | rhtl-pulp-credentials-secret |
| PULP_BASE_URL               | The base URL of the Pulp server                                                                       | No       | -                            |
| PULP_API_ROOT               | The API root path of the Pulp server                                                                  | Yes      | /api/                        |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                 | No       | -                            |
| PULP_REPOSITORY             | The Pulp npm repository (for content href resolution)                                                 | No       | -                            |
| sourceDataArtifact          | Trusted Artifact containing extracted npm packages and sidecars                                       | No       | -                            |
| dataDir                     | The location where data will be stored                                                                | Yes      | /var/workdir/content         |
| filesDir                    | The relative path within dataDir where package files are located                                      | Yes      | files                        |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                           |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                           |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                           |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                            |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                        | No       | -                            |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                             | No       | -                            |
