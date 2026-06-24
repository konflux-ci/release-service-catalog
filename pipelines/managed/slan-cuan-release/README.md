# slan-cuan-release pipeline

Release pipeline for Lightwell Java artifacts (slan-cuan).

This pipeline orchestrates the complete release workflow for Java artifacts built by
PNC (Project Newcastle):

1. **Extract** -- Pull artifacts from PNC container image
2. **Sign** -- Cryptographically sign artifacts using RADAS
3. **Register** -- Upload SBOMs to Trustify for CVE tracking
4. **Publish** -- Push signed artifacts to Pulp for distribution

## Workflow Topology

The pipeline executes tasks in strict sequential order:

```
extract → sign → register → publish
```

Each task waits for its predecessor via `runAfter` dependencies. Data flows through
a shared workspace that persists the artifact directory across all stages.

## Workspaces

The pipeline requires a single shared workspace (`shared-workspace`) for artifact passing
between tasks. All tasks mount this workspace at `/var/workdir`.

Workspace binding options:
- **PersistentVolumeClaim** -- For traditional Konflux pipelines
- **Trusted Artifacts** -- Wrap tasks with use-trusted-artifact/create-trusted-artifact
- **emptyDir** -- For ephemeral single-node execution (testing only)

## Results

The pipeline propagates key results from individual tasks for downstream consumption
and Enterprise Contract policy evaluation:

- `manifest-digest` -- OCI manifest digest of the extracted PNC image
- `deliverable-dir` -- Name of the deliverable directory
- `sbom-urn` -- URN of the SBOM registered in Trustify
- `artifacts-uploaded` -- Number of artifacts uploaded to Pulp
- `artifacts-skipped` -- Number of artifacts skipped during upload
- `published-artifact-outputs` -- JSON object for Tekton Chains SLSA provenance

The `published-artifact-outputs` result contains `uri` and `digest` keys. The
`-ARTIFACT_OUTPUTS` suffix triggers Tekton Chains to generate SLSA provenance
attestations for the published artifacts.

## Required Kubernetes Secrets

Create these Kubernetes Secrets before running the pipeline:

- `registry-auth` (.dockerconfigjson) -- Docker/Podman registry authentication
- `radas-config` (Opaque) -- RADAS configuration JSON in `config.json` key
- `trustify-sso` (Opaque) -- OIDC credentials (`client-id`, `client-secret` keys)
- Custom CA certs (Opaque, optional) -- `ca.crt` key for register/publish tasks

Secret names are configurable via pipeline parameters.

## Parameters

| Name                    | Description                                                                                                                                                                                        | Optional | Default value                                             |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| taskGitUrl              | The url to the git repo where the release-service-catalog tasks to be used are stored                                                                                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision         | The revision in the taskGitUrl repo to be used                                                                                                                                                     | No       | -                                                         |
| pnc-image               | PNC container image reference to extract artifacts from. This is the image produced by Project Newcastle containing the deliverable artifacts and SBOM. Example: quay.io/pnc-builds/foo@sha256:xyz | No       | -                                                         |
| registry-auth-secret    | Kubernetes Secret name for registry authentication (.dockerconfigjson format). Points to a Docker/Podman auth config for accessing private registries                                              | Yes      | registry-auth                                             |
| force-extract           | Overwrite existing output directory if it exists. Without this flag, the extract task refuses to overwrite existing directories                                                                    | Yes      | false                                                     |
| signing-key             | Signing key name for RADAS. Identifies which signing key to use for cryptographic signatures                                                                                               | No       | -                                                         |
| radas-config-secret     | Kubernetes Secret name containing RADAS configuration JSON. The secret must have a `config.json` key with RADAS API URL and credentials                                                            | Yes      | radas-config                                              |
| requester-id            | Requester identity for signing operations. Used for audit trails and RADAS access control. Typically an email address                                                                              | Yes      | slan-cuan@example.com                                      |
| zip-root-path           | Root of the Maven repository tree inside the ZIP archive submitted to RADAS. The ZIP file structure is <ZIP_ROOT_PATH>/<maven-layout>                                                              | Yes      | repository                                                |
| product-key             | Product key for metadata tagging. Identifies the product in RADAS records and signing logs                                                                                                         | Yes      | slan-cuan                                                 |
| ignore-patterns         | Comma-separated regex patterns to exclude files from signing. Example: ".*-sources\\.jar$,.*-javadoc\\.jar$" excludes source and javadoc JARs                                                      | Yes      | ""                                                        |
| trustify-api-url        | Trustify instance API URL. The base URL for the Trustify (TPA) SBOM ingestion API. Example: https://trustify.stage.example.com                                                                      | No       | -                                                         |
| sso-token-url           | OIDC token endpoint URL. The OAuth2/OIDC token endpoint for Trustify authentication. Example: https://sso.example.com/auth/realms/token
| sso-secret-name         | Kubernetes Secret name with OIDC credentials. The secret must have `client-id` and `client-secret` keys for OAuth2 client credentials flow                                                         | Yes      | trustify-sso                                              |
| register-insecure       | Disable TLS verification for Trustify API calls. Set to "true" to skip certificate validation (not recommended for production)                                                                     | Yes      | false                                                     |
| register-retries        | Number of retry attempts for Trustify API calls. The task will retry failed API calls this many times before giving up                                                                             | Yes      | 3                                                         |
| register-ca-cert-secret | Kubernetes Secret name for custom CA certificate (optional). The secret must have a `ca.crt` key containing the PEM-encoded CA certificate. Leave empty to use system CA bundle                    | Yes      | ""                                                        |
| pulp-url                | Pulp instance base URL. The base URL for the Pulp content management system. Example: https://pulp.example.com                                                                                     | No       | -                                                         |
| pulp-repository         | Pulp Maven distribution name. The name of the target Pulp repository for artifact publishing. Example: lightwell-maven                                                                             | No       | -                                                         |
| publish-insecure        | Disable TLS verification for Pulp API calls. Set to "true" to skip certificate validation (not recommended for production)                                                                         | Yes      | false                                                     |
| publish-ca-cert-secret  | Kubernetes Secret name for custom CA certificate (optional). The secret must have a `ca.crt` key containing the PEM-encoded CA certificate. Leave empty to use system CA bundle                    | Yes      | ""                                                        |
