# rh-push-to-registry-redhat-io-idempotent-multi-component

## Overview

Multi-component idempotency test: two components in one snapshot. First release pushes both;
second release with the same snapshot filters both (idempotent). Validates that the
`filter-already-released-by-pyxis-and-file-updates` task handles multiple components correctly,
each checked independently via `image_id` in Pyxis.

## Setup

Same as [rh-push-to-registry-redhat-io-idempotent](../rh-push-to-registry-redhat-io-idempotent/README.md).
Symlink `vault/` from that suite (or from `rh-push-to-registry-redhat-io`) for secrets.

## How It Works

Sources the base idempotent `test.sh` and overrides the GitHub repo/PR/PipelineRun/Release
flow to handle two components. The `verify_release_contents` logic is inherited from the base:

1. First release pushes both components (Pyxis records created for each)
2. Test polls Pyxis for the first component's `image_id` with `rpm_manifest.rpms` check
3. Second release: filter checks each component independently — both are filtered out

## Running

```shell
integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent-multi-component
```
