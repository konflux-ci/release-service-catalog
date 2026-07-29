# upload-npm-pulp

Upload npm package tarballs to a Pulp npm repository via the synchronous
content upload API. Sets tl.compliance_level from adjacent
*.tl-compliance.json sidecars when present. Idempotent: skips packages
already present with matching sha256; fails if the same name/version
exists with different content. On skip, still applies compliance labels
(and best-effort sidecar upload to optional PULP_FILE_REPOSITORY) so
reruns can correct metadata. Requires at least one .tgz under FILES_DIR.
Business logic runs as a single plumbing-utils command (npm-release-upload)

## Parameters

| Name                        | Description                                                                                                                                           | Optional | Default value                |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | Secret with Pulp username/password keys (same as Python wheel release)                                                                                | Yes      | rhtl-pulp-credentials-secret |
| PULP_BASE_URL               | The base URL of the Pulp server                                                                                                                       | No       | -                            |
| PULP_API_ROOT               | The API root path of the Pulp server                                                                                                                  | Yes      | /api/                        |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                                                                 | No       | -                            |
| PULP_REPOSITORY             | The Pulp npm repository to upload to                                                                                                                  | No       | -                            |
| PULP_FILE_REPOSITORY        | Optional Pulp file repository for adjacent *.tl-compliance.json uploads. When empty, sidecar file uploads are skipped (compliance labels still apply) | Yes      | ""                           |
| sourceDataArtifact          | Trusted Artifact containing extracted npm packages                                                                                                    | No       | -                            |
| dataDir                     | The location where data will be stored                                                                                                                | Yes      | /var/workdir/content         |
| filesDir                    | The relative path within dataDir where package files are located                                                                                      | Yes      | files                        |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                                                                     | Yes      | 1d                           |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                                                                       | Yes      | ""                           |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                | Yes      | ""                           |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                 | No       | -                            |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                                                                        | No       | -                            |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                                                                             | No       | -                            |
