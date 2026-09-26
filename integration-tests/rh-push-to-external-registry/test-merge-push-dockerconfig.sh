#!/usr/bin/env bash
#
# Unit test for merge_push_docker_configjson_from_b64 in test.sh
# Run via integration-tests/run-suite-unit-tests.sh (CI) or automatically from run-test.sh.
#
set -euo pipefail

SCRIPT_DIR="$(
    pushd "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null || exit 1
    pwd
    popd >/dev/null || exit 1
)"
# shellcheck source=test.sh
source "${SCRIPT_DIR}/test.sh"

local_json='{"auths":{"quay.io/redhat-pending":{"auth":"local-only","email":"local@example.com"}}}'
shared_json='{"auths":{"quay.io/hacbs-release-tests":{"auth":"shared-only","email":"shared@example.com"}}}'
local_b64="$(printf '%s' "${local_json}" | base64 -w 0)"
shared_b64="$(printf '%s' "${shared_json}" | base64 -w 0)"

merged_json="$(merge_push_docker_configjson_from_b64 "${local_b64}" "${shared_b64}")"
encoded="$(printf '%s' "${merged_json}" | base64 -w 0)"
decoded="$(base64 -d <<< "${encoded}")"

if ! jq -e '.auths["quay.io/redhat-pending"].auth == "local-only"' <<< "${decoded}" >/dev/null; then
    echo "🔴 merged config missing quay.io/redhat-pending auth from local dockerconfig" >&2
    exit 1
fi
if ! jq -e '.auths["quay.io/hacbs-release-tests"].auth == "shared-only"' <<< "${decoded}" >/dev/null; then
    echo "🔴 merged config missing quay.io/hacbs-release-tests auth from shared dockerconfig" >&2
    exit 1
fi

echo "✅ merge_push_docker_configjson_from_b64 preserves auths from both inputs"
