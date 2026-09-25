# rh-direct-sign-image-batch-concurrency test

## Overview

Signing integration test using a single pre-built component and enough unique tags
for `TARGET_BATCH_COUNT` (default 16) InternalRequests. It checks that the signing
TaskRun succeeds on its first attempt and reports the expected batch totals.

Cleanup coverage requires signing with cleanup enabled. Creator-pod scoping
preserves requests from sibling batches while removing requests from prior attempts.

This suite exercises production batching and request submission through a real
`rh-advisories` release. Batch counts and success logs do not guarantee that cleanup
ran while a sibling request existed, and the suite does not force a prior-attempt orphan.
Deterministic selector and retry-cleanup cases belong to the utils tests.

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
  * PipelineRuns execute from `konflux-release-service-tenant` using the
    `konflux-integration-runner` service account and in-cluster authentication.
* `python3` (available in both the `release-service-catalog` and
  `release-service-utils` test-runner images) for
  [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py)

### Required Environment Variables
- `GITHUB_TOKEN` - GitHub personal access token
- `VAULT_PASSWORD_FILE` - Path to file containing ansible vault password
- `RELEASE_CATALOG_GIT_URL` - Release service catalog URL for the RPA
- `RELEASE_CATALOG_GIT_REVISION` - Release service catalog revision for the RPA

### Optional Environment Variables
- `KUBECONFIG` - For local runs only; CI uses in-cluster authentication.
- `CONSOLE_URL` - Optional console base URL for PipelineRun links; inferred from a local kubeconfig when available.
  Links are omitted when neither is available.
- `TARGET_BATCH_COUNT` - Expected number of signing batches (minimum `2`, default: `16`)
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
  computed tags before creating the explicit Release. Auto-release is disabled
  on this suite's ReleasePlan before the Snapshot is applied.
- Verifies `rh-direct-sign-image` succeeded with zero retries and exactly
  `TARGET_BATCH_COUNT` batches, all succeeded, with no signing batch failure messages.

#### [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py)
- Imports and calls the real `collect_signing_items`/`batch_signing_items`/
  `get_all_image_digests`/`get_signing_keys` from `rh_direct_sign_image.py`
  directly (importable here — this suite's test-runner image is built `FROM`
  `release-service-utils`), instead of reimplementing them, so batching
  behavior — including multi-arch digest expansion and the
  quay.io-\>registry.redhat.io repository conversion apply-mapping performs —
  uses production functions. Differences between the runner and signing task
  versions, registry-access signing, or previously recorded
  signatures can still change the actual batch count, which verification checks.
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
- The signing step log reports exactly the expected number of submitted batches.
- No `Internal request failed for batch` or `Batch request failure` lines appear
  in the signing step log. Unrelated numeric strings such as `404` are ignored.

## Running the test

### From a GitHub PR comment

On a PR targeting `development`, wait for the staging catalog image build for the
latest commit to succeed. Then post a new comment:

```text
/test-batch-concurrency
```

[The Pipelines-as-Code definition](../../.tekton/rh-direct-sign-image-batch-concurrency.yaml)
runs this suite in `konflux-release-service-tenant` using the PR commit's catalog
image, Git repository, and pipeline definition. It uses the existing staging E2E
secrets and the `konflux-integration-runner` service account, matching normal
IntegrationTestScenario runs. No IntegrationTestScenario registration is needed.
The comment must be from a user authorized to trigger Pipelines-as-Code runs.

This sets `MANUAL_RUN=true` on the shared E2E pipeline: the suite runs regardless
of the changed-file filter, and a failure produces a failed GitHub check.
Existing ITS runs retain their `TEST_OUTPUT` reporting behavior.
Post the comment again to rerun; editing an existing comment does not trigger it.
After each new commit, wait for that commit's image build before commenting.

Use the same utils image in the signing task and the catalog `Dockerfile` to
keep the batch-count calculation aligned with signing.

### Through the utils E2E pipeline

Set `catalogRepo` and `catalogRef` to the catalog repository and revision to test,
and use a `catalogE2eRunnerImage` built from that revision. Set `SNAPSHOT` to
reference the utils image under test; the harness patches the catalog task images
to that image. Use `PIPELINE_TEST_SUITE=rh-direct-sign-image-batch-concurrency`
and `PIPELINE_USED=rh-advisories`.

### Locally

From this suite's directory:

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
