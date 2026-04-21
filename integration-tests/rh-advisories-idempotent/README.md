# rh-advisories-idempotent test

## Overview

This test validates idempotent re-release behavior for the `rh-advisories` pipeline:

1. **First release**: all tasks run, advisory created (`skip_release=false`)
2. **Second release** (same snapshot): `filter-already-released-advisory-images` detects the
   existing advisory in Pyxis → `skip_release=true`
3. All downstream tasks are skipped; release CR still reaches `Released=True`
4. `advisory.url` is present in second release status (populated from filter result,
   not from `create-advisory`)

## Setup

### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**,
  **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you
  want to run this test suite.)
* Access to the target cluster and tenant and managed namespaces
  * **Cluster:** stg-rh01 (staging cluster)
  * **Tenant Namespace:** `dev-release-team-tenant` (local) or `rhtap-release-2-tenant` (PaC)
  * **Managed Namespace:** `managed-release-team-tenant`

### Required Environment Variables
- `GITHUB_TOKEN` - GitHub personal access token
- `VAULT_PASSWORD_FILE` - Path to file containing ansible vault password
- `RELEASE_CATALOG_GIT_URL` - Release service catalog URL for the RPA
- `RELEASE_CATALOG_GIT_REVISION` - Release service catalog revision for the RPA

### Optional Environment Variables
- `KUBECONFIG` - Kubeconfig file for cluster access
- `LARGE_SNAPSHOT_COMPONENT_COUNT` - Number of components in snapshot (default: 1)
- `LARGE_SNAPSHOT_TIMEOUT` - Pipeline timeout (default: 2h0m0s)

### Test Properties
#### [test.env](test.env)
- Contains resource names and configuration values for testing.
- Uses a single-component pre-built snapshot to minimize first release duration.

#### [test.sh](test.sh)
- Overrides standard build functions to skip builds and use pre-built images.
- Implements the two-phase idempotent test: first release then second release.
- Verifies all acceptance criteria post second release.

### Test Functions
#### [lib/test-functions.sh](../lib/test-functions.sh)
- Reusable functions for tests.

### Secrets
- Secrets are stored in ansible vault files (symlinked from `rh-advisories-large-snapshot`):
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)

## Acceptance Criteria

- Second release: all major tasks (`create-advisory`, `push-snapshot`, `verify-conforma`,
  `rh-sign-image`, etc.) appear in `skippedTasks`
- `advisory.url` present in second release `status.artifacts` (written by
  `update-cr-status-skipped` from filter result, not `create-advisory`)

## Running the test

For local testing:

```shell
../run-test.sh rh-advisories-idempotent
```

**Note:** This test runs two full releases sequentially. The first release takes
approximately 1-2 hours in staging; the second release completes quickly once the
filter detects the existing advisory.

### Debugging

Use `--skip-cleanup` to preserve resources after the test:

```shell
../run-test.sh rh-advisories-idempotent --skip-cleanup
```

### Maintenance

To update secrets:

```shell
ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" \
  --vault-password-file <vault password file>
vi /tmp/tenant-secrets.yaml
ansible-vault encrypt /tmp/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" \
  --vault-password-file <vault password file>
rm /tmp/tenant-secrets.yaml
```
