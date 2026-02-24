# rh-push-to-registry-redhat-io-idempotent-partial-fileupdates

## Overview

Partial completion test (Gap 3.2): RPA has `fileUpdates` configured. First release runs
(Pyxis complete + MR created but not merged). Second release with the same snapshot must
**proceed** (`push-snapshot` runs) because the `fileUpdates` MR is not yet merged —
validates fail-safe behavior: the filter does not over-filter when `fileUpdates` are pending.

## Setup

Same as [rh-push-to-registry-redhat-io-idempotent](../rh-push-to-registry-redhat-io-idempotent/README.md).
Symlink `vault/` from that suite for secrets.

## How It Works

Sources the base idempotent `test.sh` and overrides `verify_release_contents`:

1. First release: Pyxis record written (`image_id` + `rpm_manifest.rpms`) AND MR created
2. Test polls Pyxis until image is fully indexed (same check as base test)
3. Second release: filter sees Pyxis complete but `fileUpdates` not merged → **keeps** component
4. Verification: `push-snapshot` ran (not skipped) — fail-safe confirmed

## Running

```shell
integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent-partial-fileupdates
```
