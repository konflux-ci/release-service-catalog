# rh-direct-sign-image-batch-concurrency test

## Overview

Regression test for an incident where `rh_direct_sign_image.py`'s `submit_batches()`
submitted multiple signing batches **concurrently** (via `ThreadPoolExecutor`), and
each batch's `cleanup_existing_requests()` call deleted a *sibling* batch's still-running
`InternalRequest` instead of only stale/retried ones — causing signing failures.

This test forces that exact scenario to reproduce (pre-fix) and reproduce-and-verify (post-fix):

1. A single pre-built component is released through `rh-advisories` with **no**
   `pushSourceContainer` and a precisely-computed number of image tags.
2. The tag count is computed at runtime (not hardcoded) from the **real** signing
   `ConfigMap` and the real resolved image digest, so it reliably produces
   **exactly `TARGET_BATCH_COUNT` (default 2)** signing batches — no more, no fewer —
   regardless of how many signing keys are configured or how batch-size limits change.
3. `rh-direct-sign-image` then submits those batches concurrently.
4. The test asserts: the task succeeds with **zero retries**, exactly
   `TARGET_BATCH_COUNT` batches were written and all succeeded, and no
   `InternalRequest`/404/`ApiException` errors appear in its log (the signature of one
   batch's cleanup deleting another's request).

No component build occurs — like `rh-advisories-large-snapshot` and
`rh-advisories-idempotent`, this test releases a single static pre-built image and
skips the PR-merge/build-wait steps entirely.

## Setup

### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**,
  **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you
  want to run this test suite.)
* Access to the target cluster and tenant and managed namespaces
  * **Cluster:** stg-rh01 (staging cluster)
  * **Tenant Namespace:** `dev-release-team-tenant` (local and ITS runs)
  * **Managed Namespace:** `managed-release-team-tenant`
  * Konflux ITS PipelineRuns execute from `konflux-release-service-tenant`
    using in-cluster authentication
* `python3` (available in both the `release-service-catalog` and
  `release-service-utils` test-runner images) for
  [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py)

### Required Environment Variables
- `GITHUB_TOKEN` - GitHub personal access token
- `VAULT_PASSWORD_FILE` - Path to file containing ansible vault password
- `RELEASE_CATALOG_GIT_URL` - Release service catalog URL for the RPA
- `RELEASE_CATALOG_GIT_REVISION` - Release service catalog revision for the RPA

### Optional Environment Variables
- `KUBECONFIG` - For local runs only; Konflux ITS use in-cluster auth
- `TARGET_BATCH_COUNT` - Exact number of concurrent signing batches to force (default: `2`)
- `BATCH_TEST_TIMEOUT` - Managed pipeline/task timeout (default: `45m0s`)

### Test Properties
#### [test.env](test.env)
- Contains resource names and configuration values for testing.
- Uses a single pre-built component so the test completes quickly.

#### [test.sh](test.sh)
- Overrides standard build functions to skip builds and use a pre-built image
  (first entry of `rh-advisories-large-snapshot`'s stable image pool).
- Resolves the real image digest, then computes the exact tag count needed
  for `TARGET_BATCH_COUNT` batches via
  [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py) (which
  resolves the real signing key(s) itself from the live signing `ConfigMap`).
- Patches the `ReleasePlanAdmission`'s single component mapping with the
  computed tags before applying the Snapshot (auto-release fires the moment
  the Snapshot lands, so the RPA must be correct beforehand).
- Verifies `rh-direct-sign-image` succeeded with zero retries and exactly
  `TARGET_BATCH_COUNT` batches, all succeeded, with no cross-batch cleanup errors.

#### [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py)
- Imports and calls the real `collect_signing_items`/`batch_signing_items`/
  `get_all_image_digests`/`get_signing_keys` from `rh_direct_sign_image.py`
  directly (importable here — this suite's test-runner image is built `FROM`
  `release-service-utils`), instead of reimplementing them, so batching
  behavior — including multi-arch digest expansion and the
  quay.io-\>registry.redhat.io repository conversion apply-mapping performs —
  always matches production exactly.
- Linear-searches for the smallest tag count that produces exactly
  `TARGET_BATCH_COUNT` batches, and adds a small margin so the test isn't
  sitting exactly on a batch-size boundary.

### Test Functions
#### [lib/test-functions.sh](../lib/test-functions.sh)
- Reusable functions for tests.

### Resources
Several resources are symlinked, unchanged, from `rh-advisories-large-snapshot`
(they only differ by variable *values* substituted from this suite's
[test.env](test.env), not by content):
- `resources/tenant/{application,component,sa,sa-rolebinding,rp,kustomization}.yaml`
- `resources/managed/{sa,sa-rolebinding,ec-policy,kustomization}.yaml`
- `vault/{tenant-secrets,managed-secrets}.yaml`

Only `resources/managed/rpa.yaml` is unique to this suite (single named
component instead of a 200-component wildcard mapping, no `fileUpdates`
block, and a shorter pipeline timeout).

### Secrets
- Secrets are stored in ansible vault files (symlinked from `rh-advisories-large-snapshot`):
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)

## Acceptance Criteria

- Release reaches `Released=True`.
- The `rh-direct-sign-image` `TaskRun` succeeds on its first attempt
  (`status.retriesStatus` has zero entries).
- Its pod log reports `Wrote <TARGET_BATCH_COUNT> batch(es)` and
  `Batch request summary: <TARGET_BATCH_COUNT> succeeded, 0 failed`.
- No `Internal request failed for batch`, `Batch request failure`, `404`, or
  `ApiException` lines appear in the log.

## Running the test

For local testing:

```shell
../run-test.sh rh-direct-sign-image-batch-concurrency
```

### Debugging

Use `--skip-cleanup` to preserve resources after the test:

```shell
../run-test.sh rh-direct-sign-image-batch-concurrency --skip-cleanup
```

To force a different number of batches (e.g. to check the 2→3 boundary):

```shell
TARGET_BATCH_COUNT=3 ../run-test.sh rh-direct-sign-image-batch-concurrency
```

### Maintenance

To update secrets, edit them in `rh-advisories-large-snapshot/vault/` (this
suite's vault files are symlinks to that suite's):

```shell
ansible-vault decrypt ../rh-advisories-large-snapshot/vault/tenant-secrets.yaml \
  --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
vi /tmp/tenant-secrets.yaml
ansible-vault encrypt /tmp/tenant-secrets.yaml \
  --output "../rh-advisories-large-snapshot/vault/tenant-secrets.yaml" \
  --vault-password-file <vault password file>
rm /tmp/tenant-secrets.yaml
```
