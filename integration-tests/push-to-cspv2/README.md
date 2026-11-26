# push-to-cspv2 test
## Setup
### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
  * Requires a `push-to-cspv2-base` branch containing a Dockerfile (content is not
    otherwise exercised by this test, since the pipeline doesn't yet act on the
    snapshot's artifacts).
* GitHub personal access token (classic) for above repo with **admin:repo_hook**,
  **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you
  want to run this test suite.)
* Access to the target cluster and tenant and managed namespaces
  * This test uses stg-rh01 and the dev-release-team-tenant and managed-release-team-tenant
    namespaces.

### Required Environment Variables
- GITHUB_TOKEN
  - The GitHub personal access token needed for repo operations
- VAULT_PASSWORD_FILE
  - Path to a file that contains the ansible vault password needed to decrypt the
    secrets needed for testing.
- RELEASE_CATALOG_GIT_URL
  - The release service catalog URL to use in the RPA
- RELEASE_CATALOG_GIT_REVISION
  - The release service catalog revision to use in the RPA

### Test Properties
#### [test.env](test.env)
- Contains resource names and configuration values needed for testing. Since this test
  requires internal services, the tenant and managed namespaces should remain as-is.
#### [test.sh](test.sh)
- Verifies the Release reached `Released=True` and that the `push-to-cspv2` TaskRun ran
  exactly once, succeeded, reported `pushResult=Success`, and that its `expectedChecksum`
  and `actualChecksum` results match.

### Secrets
- Secrets needed for testing are stored in ansible vault files:
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml) — PaC webhook secret
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml) — placeholder only; this
    pipeline does not currently need any managed-namespace secrets

### Running the test

```shell
run-test.sh push-to-cspv2
```

### Debugging

Use `--skip-cleanup` to examine resources after the test ends.

### Scope

This is an initial setup for the `push-to-cspv2` pipeline, not yet implementing any
CSPv2-specific logic. It's a basic starting point for future development: an internal
task downloads a small public OCI artifact from Quay with `oras` and verifies the
downloaded file's checksum against the digest declared in the artifact's manifest.
CSPv2-specific fetch/sign/push and metadata update logic will replace this in follow-up
pipeline and test changes.
