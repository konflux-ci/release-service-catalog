# rh-push-to-registry-redhat-io-idempotent-added-component

## Overview

Tests **Gap 2.2** from the idempotency coverage analysis: the "snapshot grows between
releases" scenario. Validates that the `filter-already-released-by-pyxis-and-file-updates`
task correctly distinguishes between components that were already released and new ones
added to the snapshot in a subsequent release.

## What This Proves

- A component already indexed in Pyxis (`component-a`) is **filtered** from the second release
- A newly added component (`component-b`, not yet in Pyxis) is **pushed** by the second release
- The filter operates **per-component**, not at the snapshot level

## Test Flow

This test runs in two phases, using the standard `run-test.sh` orchestration for Phase 1
and performing Phase 2 entirely inside `verify_release_contents`.

### Phase 1 (standard run-test.sh flow — component-a only)

1. GitHub branches created for **both** components upfront (so component-b is ready)
2. Kubernetes resources applied for **component-a only** (kustomization excludes `component2.yaml`)
3. component-a builds via PaC → Konflux creates a **1-component snapshot**
4. Auto-release triggers with that 1-component snapshot → component-a pushed to registry + Pyxis

### Phase 2 (inside `verify_release_contents`)

5. Pyxis polled until component-a's `image_id` + `rpm_manifest.rpms` are present (confirming
   the filter task will detect it as already-released)
6. component-b's PaC secret and `Component` CR applied dynamically
7. Konflux detects the new Component, PaC opens a PR on component-b's branch
8. PR merged → component-b build PLR runs → Konflux creates a **2-component snapshot**
   (component-a with its existing digest + component-b with its new digest)
9. Auto-release triggers for the 2-component snapshot
10. Filter task runs:
    - `component-a`: found in Pyxis with `rpm_manifest.rpms` → **FILTERED**
    - `component-b`: not found in Pyxis → **KEPT**
    - `skip_release=false` → `push-snapshot` runs for component-b only
11. Test asserts push-snapshot ran and filter logs confirm per-component decisions

## Architecture Notes

### Why component2.yaml is not in kustomization.yaml

The `resources/tenant/kustomization.yaml` deliberately **excludes** `component2.yaml`.
This ensures Phase 1 creates only a 1-component application, so the first snapshot
(and Release) contains only component-a. `component2.yaml` is applied manually via
`kubectl create` in Phase 2.

### Secrets

Both components share the same managed credentials (push, Pyxis, signing) under
`component_name`. Component-b's PaC secret (`pipelines-as-code-secret-${component2_name}`)
is generated in `decrypt_secrets` from the base idempotent suite's vault and applied
in Phase 2. Managed secrets are copied from the base suite (same vault).

### Cleanup

component-b's `Component` CR is applied dynamically and is **not** in
`kustomization.yaml`, so the standard cleanup trap does not delete it. It is cleaned up
by `cleanup_old_resources` at the start of the **next** test run (matches
`originating-tool: rh-push-registry-rh-io-idem-added-comp-e2e-test`, age > 24h).

## Setup

Same prerequisites as
[rh-push-to-registry-redhat-io-idempotent](../rh-push-to-registry-redhat-io-idempotent/README.md).
The vault files from that suite are reused (no separate vault needed).

## Running

```shell
integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent-added-component
```

## Expected Runtime

~35–45 minutes (two full build+release cycles plus Pyxis polling between them).

## Related

- **Gap analysis doc:** `IDEMPOTENCY_TEST_COVERAGE.md` § Gap 2.2
- **Base idempotent test:** `integration-tests/rh-push-to-registry-redhat-io-idempotent/`
- **Multi-component test (Gap 2.1):** `integration-tests/rh-push-to-registry-redhat-io-idempotent-multi-component/`
- **Filter task:** `tasks/managed/filter-already-released-by-pyxis-and-file-updates/`
