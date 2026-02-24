#!/usr/bin/env bash
#
# test.sh - Multi-arch / manifest list idempotency
#
# Same flow as base idempotent test; component uses docker-build-multi-platform-oci-ta
# so the snapshot has a manifest list digest. Filter queries Pyxis by that digest.
#

# shellcheck source=../rh-push-to-registry-redhat-io-idempotent/test.sh
source "${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent/test.sh"
