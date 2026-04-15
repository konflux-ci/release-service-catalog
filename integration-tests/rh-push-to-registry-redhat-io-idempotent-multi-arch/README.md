# rh-push-to-registry-redhat-io-idempotent-multi-arch

## Overview

Idempotency test with a multi-architecture component: uses `docker-build-multi-platform-oci-ta`
so the build produces a manifest list and the snapshot contains a manifest list digest. Same
two-release idempotent flow as the base test — validates that the filter handles manifest
list digests correctly via the `image_id` field query.

## Setup

Same as [rh-push-to-registry-redhat-io-idempotent](../rh-push-to-registry-redhat-io-idempotent/README.md).
Symlink `vault/` from that suite for secrets. Build may take longer than single-arch.

## How It Works

Sources the base idempotent `test.sh` without overrides. The manifest list digest is stored
by `create-pyxis-image` as `image_id`, which the filter task queries directly. No special
handling is needed for multi-arch images — the query and completeness check are identical.

## Running

```shell
integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent-multi-arch
```
