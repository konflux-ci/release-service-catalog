# upload-npm-pulp

Upload npm package tarballs to a Pulp npm repository via the synchronous
content upload API. Sets tl.compliance_level from adjacent
*.tl-compliance.json sidecars when present. When ATTESTATION_IMAGE_PREFIX
(or COMPLIANCE_IMAGE_PREFIX) is set, signs adjacent .tgz with cosign
(generate-and-sign-npm-attestations), pushes attestation OCI to Quay, and
sets tl.oci_registry_base / tl.attestation_oci_digest /
tl.attestation_predicate_type. Idempotent: skips packages already present
with matching sha256; fails if the same name/version exists with different
content. On skip, still applies compliance and attestation labels so
reruns can attach metadata. Requires at least one .tgz under FILES_DIR.
Business logic runs as npm-release-upload in the slan-cuan image.

## Parameters

| Name                        | Description                                                                                                                                                  | Optional | Default value                     |
|-----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------|
| SERVICE_ACCOUNT_SECRET_NAME | Secret with Pulp username/password keys (same as Python wheel release)                                                                                       | Yes      | rhtl-pulp-credentials-secret      |
| COSIGN_SECRET_NAME          | Secret with cosign.key or SIGN_KEY + AWS_* for package attestations. Attestation is skipped when signing material is absent unless REQUIRE_ATTESTATIONS=true | Yes      | konflux-cosign-signing-production |
| REQUIRE_ATTESTATIONS        | When true, fail if signing material or .att files are missing                                                                                                | Yes      | false                             |
| PULP_BASE_URL               | The base URL of the Pulp server                                                                                                                              | No       | -                                 |
| PULP_API_ROOT               | The API root path of the Pulp server                                                                                                                         | Yes      | /api/                             |
| PULP_DOMAIN                 | The domain to use for Pulp operations                                                                                                                        | No       | -                                 |
| PULP_REPOSITORY             | The Pulp npm repository to upload to                                                                                                                         | No       | -                                 |
| PULP_FILE_REPOSITORY        | Optional Pulp file repository for adjacent *.tl-compliance.json uploads. When empty, sidecar file uploads are skipped (compliance labels still apply)        | Yes      | ""                                |
| COMPLIANCE_IMAGE_PREFIX     | Quay repository prefix used for attestation OCI (and shared tl.oci_registry_base). Empty skips sign + attestation publish                                    | Yes      | ""                                |
| ATTESTATION_IMAGE_PREFIX    | Optional override for attestation OCI repo. Defaults to COMPLIANCE_IMAGE_PREFIX when empty                                                                   | Yes      | ""                                |
| sourceDataArtifact          | Trusted Artifact containing extracted npm packages                                                                                                           | No       | -                                 |
| dataDir                     | The location where data will be stored                                                                                                                       | Yes      | /var/workdir/content              |
| filesDir                    | The relative path within dataDir where package files are located                                                                                             | Yes      | files                             |
| ociArtifactExpiresAfter     | Expiration date for the trusted artifacts created                                                                                                            | Yes      | 1d                                |
| orasOptions                 | oras options to pass to Trusted Artifacts calls                                                                                                              | Yes      | ""                                |
| trustedArtifactsDebug       | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                                                       | Yes      | ""                                |
| taskGitUrl                  | The url to the git repo where the release-service-catalog tasks and stepactions to be used are stored                                                        | No       | -                                 |
| taskGitRevision             | The revision in the taskGitUrl repo to be used                                                                                                               | No       | -                                 |
| ociStorage                  | The OCI repository where the Trusted Artifacts are stored                                                                                                    | No       | -                                 |
