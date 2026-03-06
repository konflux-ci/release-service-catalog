# rh-push-to-registry-redhat-io-idempotent test

## Overview

This test validates idempotent release behavior for the `rh-push-to-registry-redhat-io` pipeline
(RELEASE-1265). It verifies that when a second release is created with the same snapshot, the
`filter-already-released-by-pyxis-and-file-updates` task correctly filters all components, and
the `push-snapshot` task is skipped.

## Setup

### Dependencies

* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**, **delete_repo**,
  **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you want to run
  this test suite.)
* Access to the target cluster and tenant and managed namespaces
  * This test uses stg-rh01 and the dev-release-team-tenant and managed-release-team-tenant
    namespaces.

### Required Environment Variables

- GITHUB_TOKEN
  - The GitHub personal access token needed for repo operations
  - The repo in question can be located in [test.env](test.env)
- VAULT_PASSWORD_FILE
  - This is the path to a file that contains the ansible vault
    password needed to decrypt the secrets needed for testing.
- RELEASE_CATALOG_GIT_URL
  - The release service catalog URL to use in the RPA
  - This is provided when testing PRs
- RELEASE_CATALOG_GIT_REVISION
  - The release service catalog revision to use in the RPA
  - This is provided when testing PRs

### Optional Environment Variables

- KUBECONFIG
  - The KUBECONFIG file to used to login to the target cluster
  - This is provided when testing PRs

### Test Properties

#### [test.env](test.env)

- This file contains resource names and configuration values needed for testing.
- Since this test requires internal services, the tenant and managed namespaces
  should remain as-is.

### Test Functions

#### [lib/test-functions.sh](../lib/test-functions.sh)

- This file contains re-usable functions for testing

### Secrets

- Secrets needed for testing are stored in ansible vault files (symlinked from
  [rh-push-to-registry-redhat-io](../rh-push-to-registry-redhat-io)):
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)

### Running the test

This test validates idempotent release behavior by creating two releases with the same snapshot
and verifying that the second release correctly filters already-released components.

**Pyxis-only filtering**: The RPA omits `fileUpdates` because hacbs-release-tests GitLab does
not auto-merge MRs. The filter checks Pyxis using the `image_id` field (manifest digest stored
by `create-pyxis-image`) and requires `rpm_manifest.rpms` to be non-empty (populated by
`push-rpm-data-to-pyxis`). Both conditions must be true for a component to be filtered out.

After the first release, the test polls Pyxis from within the cluster until both conditions
are satisfied, then creates the second release.

```shell
integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent
```

### Debugging

There is a `--skip-cleanup` option to the script in the event that you want to examine the
resources after a test has ended.

### Pyxis Query Strategy

The `filter-already-released-by-pyxis-and-file-updates` task queries Pyxis using:

- **Query field**: `image_id==sha256:...`
  - `image_id` is the manifest digest as stored by `create-pyxis-image`
  - `docker_image_digest` does **not** exist in Pyxis records and always returns empty results
- **Completeness check**: `rpm_manifest.rpms` must be non-empty
  - Populated by `push-rpm-data-to-pyxis` after `create-pyxis-image`
  - A record with no RPM data means `push-rpm-data-to-pyxis` has not yet completed

The test's polling job mirrors this logic exactly: it waits until the `image_id` query returns
a record **and** that record has non-empty `rpm_manifest.rpms` before creating the second release.

#### Polling Strategy (from cluster)

Polling runs as a Kubernetes Job inside the managed namespace (to use the cluster CA and Pyxis
credentials). On each 30s poll cycle:

1. **Primary** — `image_id` query with RPM data check: `image_id==sha256:...`
   - Succeeds only when both `create-pyxis-image` and `push-rpm-data-to-pyxis` are complete
   - This is the canonical check; matches exactly what the filter task requires
2. **Fallback** — repository existence check: `repositories.repository==rhtap/rh-advisories-component`
   - Note: Pyxis uses the short path form (slash-separated), not the full URL with dashes
   - Used only as a diagnostic indicator; does not unlock Phase 2 on its own

#### Expected Poll Output

```
[0s / 60s] Checking Pyxis...
  ✅ image_id query (with RPM data): Found with RPM data (42 rpms)!

✅ Image IS in Pyxis (found via image_id) with RPM data — filter task will skip this component
```

If RPM data isn't ready yet:
```
[0s / 60s] Checking Pyxis...
  ⏳ image_id query (with RPM data): Image found but rpm_manifest.rpms empty (push-rpm-data-to-pyxis pending)
[30s / 60s] Checking Pyxis...
  ✅ image_id query (with RPM data): Found with RPM data (42 rpms)!
```

#### Troubleshooting

If the test fails with "Pyxis indexing timeout":

1. **Increase wait time**:
   ```bash
   export IDEMPOTENT_WAIT_SECONDS=300
   ```

2. **Verify first release wrote to Pyxis** — check `create-pyxis-image` and
   `push-rpm-data-to-pyxis` task status in the first release's managed pipeline

3. **Check the filter task logs** in the second release's managed pipeline:
   ```bash
   kubectl logs -n managed-release-team-tenant \
     -l tekton.dev/taskRun=<filter-taskrun-name> \
     -c step-filter-already-released-by-metadata --tail=100
   ```
   Look for: `Image found in Pyxis for <component> with RPM data (N rpms)`.
   If it says `no RPM data` — `push-rpm-data-to-pyxis` hadn't finished when Phase 2 started.

### Maintenance

- Vault files are symlinked from `rh-push-to-registry-redhat-io`. To update secrets, edit the
  vault files in that suite.
- Should you require to add or update a secret, follow these steps in the
  [rh-push-to-registry-redhat-io](../rh-push-to-registry-redhat-io) suite:

```shell
ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
vi /tmp/tenant-secrets.yaml
```

```shell
ansible-vault encrypt /tmp/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
rm /tmp/tenant-secrets.yaml
```
