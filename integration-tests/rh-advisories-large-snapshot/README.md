# rh-advisories-large-snapshot test

## Overview

Stress test for the `rh-advisories` release pipeline using a **static pool of
200 pre-built single-arch images** (`resources/static-image-pool-stable.txt`).
There is no image build step — images already exist in Quay and are selected
directly from the pool.

| Property | Value |
|---|---|
| Components | 200 |
| Tags per component | 4 (2 run-unique + 2 static; ×200 = 800 total, 400 fresh per run) |
| Managed pipeline duration | 1h 30 min |

> **Note:** duration varies significantly with Pyxis signing service load.
> Weekday peak hours tend to be slower; weekends and off-peak hours are faster.


## Trigger comment

| Comment | Pipeline |
|---|---|
| `/test-large-snapshot` | upstream `rh-advisories.yaml` |

Trigger is defined in `.tekton/rh-advisories-large-snapshot.yaml`.

Static pool images are used as-is — **no digest mutation needed**. Pyxis signing
idempotency is keyed on `(digest, repo:tag, signing_key)` tuples. Each run
assigns 2 run-unique UUID-based tags per component (`<name>-<uuid>`,
`<name>-v1.0.<uuid>`), so each run presents 400 tag+digest combinations Pyxis
has never seen before, forcing 400 fresh signing operations. The 2 static tags
(`<name>-v1.0`, `<name>-stable`) are idempotent after the first run and
contribute no additional signing load.

## Setup

### Dependencies

- GitHub repo: <https://github.com/hacbs-release-tests/e2e-base>
- GitHub personal access token (classic) for the above repo with
  **admin:repo_hook**, **delete_repo**, **repo** scopes.
- The password to the vault files. (Contact a member of the Release team.)
- Access to the target cluster and namespaces:
  - Cluster: `stg-rh01`
  - Tenant namespace: `dev-release-team-tenant`
  - Managed namespace: `managed-release-team-tenant`

### Required Environment Variables

- `GITHUB_TOKEN` — personal access token for GitHub repo operations
  (repo location in [test.env](test.env))
- `VAULT_PASSWORD_FILE` — path to a file containing the Ansible Vault password
  needed to decrypt test secrets
- `RELEASE_CATALOG_GIT_URL` — release-service-catalog URL used in the RPA
  (provided automatically when testing PRs)
- `RELEASE_CATALOG_GIT_REVISION` — catalog revision used in the RPA
  (provided automatically when testing PRs)

### Optional Environment Variables

- `KUBECONFIG` — kubeconfig file for the target cluster (provided
  automatically when testing PRs)
- `FRESH_BUILDS_FILE` — path to an alternative image list file (default: the
  bundled `resources/static-image-pool-stable.txt`)

### Test Properties

#### [test.env](test.env)

Contains resource names and configuration values (namespaces, timeouts,
feature flags). Sourced automatically before [test.sh](test.sh).

#### [test.sh](test.sh)

Main test orchestrator: selects images from the pool, creates the Snapshot and
Release, and waits for the managed pipeline to succeed.

### Test Functions

#### [lib/test-functions.sh](../lib/test-functions.sh)

Reusable helper functions shared across test suites.

### Secrets

Secrets are stored in Ansible Vault files:

- [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
- [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)

## Concurrency

Two concurrent runs will not corrupt each other's data — each run uses its
PipelineRun UID to scope resource names and per-component tags
(`<name>-<uuid>`, `<name>-v1.0.<uuid>`, `<name>-v1.0`, `<name>-stable`).
However, concurrent runs will make each other slower due to Pyxis rate
limiting. The recommendation is to run one at a time.

## Running the test

On a PR, comment:

```
/test-large-snapshot
```

Or locally:

```shell
../run-test.sh rh-advisories-large-snapshot
```

## Debugging

There is a `--skip-cleanup` option to the script if you want to examine
resources after the test ends.

### Failure reporting

The `test-report` finally task always runs and actively diagnoses failures:

- **Pre-pipeline failures** (e.g. `generate-large-snapshot.sh` errors): the
  failed component, step, command, and exit code are shown.
- **Managed pipeline failures** (e.g. `apply-mapping`, `rh-direct-sign-image`): the
  `test-report` task queries the cluster directly and shows the failed task
  name, TaskRun name, Tekton condition message, and — if the pod has not yet
  been garbage-collected — the last matching error lines from the pod log
  (filtered for `fatal`, `error`, `403`, `404`, etc.).

This means a transient Quay 403/404 on a specific image is immediately visible
in the test-report output without having to dig through truncated step logs.
