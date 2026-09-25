# rh-direct-sign-image-batch-concurrency test

## Overview

Signing integration test using a single, freshly-built component and enough unique tags
for `TARGET_BATCH_COUNT` (default 26) InternalRequests. It checks that the signing
TaskRun ultimately succeeds and that its first attempt reports the expected batch
totals. A Tekton-level retry is tolerated (logged as a note, not a failure) rather
than required — see Acceptance Criteria below.

Cleanup coverage requires signing with cleanup enabled. Creator-pod scoping
preserves requests from sibling batches while removing requests from prior attempts.

This suite exercises production batching and request submission through a real
`rh-advisories` release. Batch counts and success logs do not guarantee that cleanup
ran while a sibling request existed, and the suite does not force a prior-attempt orphan.
Deterministic selector and retry-cleanup cases belong to the utils tests.

The default of 26 is kept close to the minimum that clears `rh-direct-sign-image`'s
`concurrentLimit` (24): `submit_batches()`'s `ThreadPoolExecutor` only starts a batch
beyond the first 24 once an earlier batch frees a worker slot, so any count past 24
gives a "late dispatch" event a chance to land while another same-pod sibling is still
mid-flight — the condition cleanup's creator-pod scoping is meant to handle. This only
raises the odds of exercising that condition on any given run; it is not a guarantee,
since it depends on real signing-latency variance between batches. The count is kept
close to the 24 floor, rather than much higher, because every tag is also cosign-signed
by `rh-sign-image-cosign` onto one shared signature manifest *per destination
repository* — confirmed empirically to hit Quay's upload size limit (`413 Request
Entity Too Large`) at around 275 tags on a single repository. To stay comfortably
under that limit while still forcing enough batches to clear `concurrentLimit`, this
suite's RPA spreads its ~650 computed tags across **4** destination repositories
(~165 tags each) instead of 1 — see `mapping.components[0].repositories` in
[resources/managed/rpa.yaml](resources/managed/rpa.yaml). Those repositories are
registered in Pyxis stage via
[releng/pyxis-repo-configs](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs)
(`products/release-service-batch-test/release-service-batch-test.yaml`).

A real component build runs every execution, via the standard
`create_github_repositories`/`merge_github_prs`/`wait_for_plrs_to_complete` flow
(same as `rh-advisories-idempotent`), so every run signs a genuinely fresh, unique
image digest. This matters because this suite signs a large number of tags onto
one shared per-repository cosign signature manifest (see below): reusing a static
digest across runs would accumulate signatures on that manifest indefinitely (and
risk two concurrent runs colliding on the same manifest), eventually exceeding
Quay's upload size limit. The component builds from
[hacbs-release-tests/e2e-base](https://github.com/hacbs-release-tests/e2e-base)'s
`collectors-base` branch (`FROM ubi9` plus labels, no real compilation), so the
build itself is fast.

This suite's RPA sets `sign.cosignSecretName`, matching `rh-advisories-large-snapshot`.
`process-component-sbom` consumes the same `collect-task-params` extracted value
unconditionally (it has no `when` gate on it, unlike `rh-sign-image-cosign`), and
Kubernetes rejects pod creation outright if that value resolves to an empty
`secretKeyRef.name`. Leaving `cosignSecretName` unset to try to skip
`rh-sign-image-cosign` breaks `process-component-sbom` instead and fails the whole
release before signing is ever reached.

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
- `TARGET_BATCH_COUNT` - Expected number of signing batches (minimum `2`, default: `26`)
- `BATCH_TEST_TIMEOUT` - Managed pipeline/task timeout (default: `2h30m0s`)

### Test Properties
#### [test.env](test.env)
- Contains resource names and configuration values for testing.
- Uses a single component, built from a minimal base image, so the build completes quickly.

#### [test.sh](test.sh)
- Uses the standard build functions (no overrides) to build and push a fresh
  component image every run via a real GitHub PR. Auto-release is disabled on
  this suite's ReleasePlan before the build starts, so the Snapshot Konflux
  auto-creates when the build completes doesn't trigger a release on its own.
- Once the build completes, discovers that auto-created Snapshot and resolves
  its digest, then computes the exact tag count needed for `TARGET_BATCH_COUNT`
  batches via
  [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py) (which
  resolves the real signing key(s) itself from the live signing `ConfigMap`).
  The calculation includes the image timestamp tag that `apply-mapping` adds
  implicitly before signing and queries Pyxis to include registry-access
  references under the same conditions as the release pipeline.
- Patches the `ReleasePlanAdmission`'s single component mapping with the
  computed tags, split into roughly equal contiguous chunks across all 4
  configured repositories, before creating the explicit Release. Auto-release
  is disabled on this suite's ReleasePlan before the Snapshot is applied.
- Verifies `rh-direct-sign-image` ultimately succeeded and that its first
  attempt submitted exactly `TARGET_BATCH_COUNT` batches. A Tekton-level retry
  is tolerated (logged as a note, not a failure) rather than required to be
  zero: pushing concurrency above `concurrentLimit` to exercise the sibling
  path can also trip an unrelated transient infra error (e.g. a 409 Conflict
  updating the namespace `ResourceQuota` under heavy concurrent
  InternalRequest creation), and that isn't a cleanup-correctness bug.

#### [utils/compute_batch_tag_count.py](utils/compute_batch_tag_count.py)
- Imports and calls the real `collect_signing_items`/`batch_signing_items`/
  `get_all_image_digests`/`get_signing_keys` from `rh_direct_sign_image.py`
  directly (importable here — this suite's test-runner image is built `FROM`
  `release-service-utils`), instead of reimplementing them, so batching
  behavior — including multi-arch digest expansion, registry-access signing,
  the implicit image timestamp tag, and the
  quay.io-\>registry.redhat.io repository conversion apply-mapping performs —
  uses production functions. Differences between the runner and signing task
  versions or previously recorded signatures can still change the actual batch
  count, which verification checks.
- Uses exponential and binary search to find the smallest tag count that
  produces exactly `TARGET_BATCH_COUNT` batches, then adds a small margin so
  the test isn't sitting exactly on a batch-size boundary.

### Test Functions
#### [lib/test-functions.sh](../lib/test-functions.sh)
- Reusable functions for tests.

### Resources
Several resources are symlinked, unchanged, from `rh-advisories-large-snapshot`
(they only differ by variable *values* substituted from this suite's
[test.env](test.env), not by content):
- `resources/tenant/{application,sa,sa-rolebinding,rp,kustomization}.yaml`
- `resources/managed/{sa,sa-rolebinding,ec-policy,kustomization}.yaml`
- `vault/{tenant-secrets,managed-secrets}.yaml`

Two resources are unique to this suite:
- `resources/managed/rpa.yaml` (single named component mapped to 4 destination
  repositories instead of a 200-component wildcard mapping, no `fileUpdates`
  block, and a shorter pipeline timeout).
- `resources/tenant/component.yaml` — unlike `rh-advisories-large-snapshot`
  (which never builds anything), this suite performs a real build every run,
  so its `Component` needs a `build.appstudio.openshift.io/pipeline`
  annotation for Pipelines-as-Code to resolve a build pipeline (matches
  `rh-advisories-idempotent`'s component.yaml).

### Secrets
- Secrets are stored in ansible vault files (symlinked from `rh-advisories-large-snapshot`):
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)

## Acceptance Criteria

- Release reaches `Released=True`.
- Exactly one `rh-direct-sign-image` `TaskRun` exists and it ultimately
  succeeds. `status.retriesStatus` is logged, not required to be zero (see
  above).
- Its *first attempt's* pod log reports `Wrote <TARGET_BATCH_COUNT> batch(es)`
  and submits exactly `TARGET_BATCH_COUNT` batches — this is a hard
  requirement regardless of retries, since only the first attempt (before
  anything is signed) can show the full intended batch split.
- The first attempt's `Batch request summary: <TARGET_BATCH_COUNT> succeeded,
  0 failed` and absence of `Internal request failed for batch`/`Batch request
  failure` lines are hard requirements when there were zero retries, and
  informational notes (not failures) when a later retry recovered.
  Unrelated numeric strings such as `404` are ignored.

## Running the test

### Through a catalog pull request

The shared
[`stage-release-service-catalog-pull-request.yaml`](../../.tekton/stage-release-service-catalog-pull-request.yaml)
PipelineRun builds the catalog image for a pull request and produces its Snapshot.
The `rh-direct-sign-image-batch-concurrency-e2e-test` `IntegrationTestScenario`
then runs this suite through `integration-tests/pipelines/e2e-tests-staging-pipeline.yaml`
with `PIPELINE_USED=rh-advisories`. The scenario is registered outside this
repository in `konflux-release-data`; this suite does not need a dedicated
Pipelines-as-Code definition.

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
