# upload-npm-closure

Publish TL npm closure metadata after Pulp upload: for each assess
*.tl-compliance.json sidecar under FILES_DIR, push per-package compliance
OCI and update the global closure index on Quay. COMPLIANCE_IMAGE_PREFIX,
CLOSURE_INDEX_IMAGE, and TL_NPM_REGISTRY_URL are task params (defaults keep
calunga npm PoC behaviour). Requires Pulp credentials (same secret as
upload-npm-pulp). Business logic runs as npm-release-closure-update.

## Parameters

| Name                        | Description                                                                                           | Optional | Default value                                                                            |
|-----------------------------|-------------------------------------------------------------------------------------------------------|----------|------------------------------------------------------------------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | Secret with Pulp username/password keys (same as upload-npm-pulp)                                     | Yes      | rhtl-pulp-credentials-secret                                                             |
| PULP_BASE_URL               | The base URL of the Pulp server                                                                       | No       | -                                                                                        |
| PULP_API_ROOT               | The API root path of the Pulp server                                                                  | Yes      | /api/                                                                                    |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                 | No       | -                                                                                        |
| PULP_REPOSITORY             | The Pulp npm repository (for content href resolution)                                                 | No       | -                                                                                        |
| COMPLIANCE_IMAGE_PREFIX     | Quay repository prefix for per-package *.tl-compliance.json OCI                                       | Yes      | quay.io/redhat-user-workloads/calunga-tenant/calunga-npm-registry-main                   |
| CLOSURE_INDEX_IMAGE         | Quay image reference for the global npm-closure-index artifact                                        | Yes      | quay.io/redhat-user-workloads/calunga-tenant/calunga-npm-registry-main:npm-closure-index |
| TL_NPM_REGISTRY_URL         | Content URL used when resolving TL npm packages during closure update                                 | Yes      | https://packages.redhat.com/api/pulp-content/public-trusted-libraries/javascript         |
| sourceDataArtifact          | Trusted Artifact containing extracted npm packages and sidecars                                       | No       | -                                                                                        |
| dataDir                     | The location where data will be stored                                                                | Yes      | /var/workdir/content                                                                     |
| filesDir                    | The relative path within dataDir where package files are located                                      | Yes      | files                                                                                    |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                     | Yes      | 1d                                                                                       |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                       | Yes      | ""                                                                                       |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                | Yes      | ""                                                                                       |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored | No       | -                                                                                        |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                        | No       | -                                                                                        |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                             | No       | -                                                                                        |
