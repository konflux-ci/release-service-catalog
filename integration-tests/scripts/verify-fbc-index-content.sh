#!/usr/bin/env bash
# Verify that a published FBC index image contains valid OLM catalog entries
# by rendering it with opm and asserting on the output.
#
# Uses the shared opm-render-cached.sh helper for rendering and auth setup.
#
# Usage: verify-fbc-index-content.sh <target_index> <fbc_fragment> <managed_secrets_yaml>
#
# Exit codes:
#   0 - All assertions passed
#   1 - One or more assertions failed or a required tool/input is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

target_index="${1:?Usage: verify-fbc-index-content.sh <target_index> <fbc_fragment> <managed_secrets_yaml>}"
fbc_fragment="${2:?fbc_fragment argument is required}"
managed_secrets_yaml="${3:?managed_secrets_yaml argument is required}"

# shellcheck source=opm-render-cached.sh
source "${SCRIPT_DIR}/opm-render-cached.sh"

OPM_CACHE_DIR="${OPM_CACHE_DIR:-/tmp/opm-render-cache}"
init_render_cache "${OPM_CACHE_DIR}"
trap 'cleanup_render_cache' EXIT

echo "🔍 Verifying published FBC index content"
echo "  target_index:  ${target_index}"
echo "  fbc_fragment:  ${fbc_fragment}"
echo "  cache_dir:     ${OPM_CACHE_DIR}"
echo "  DEBUG: hostname=$(hostname 2>/dev/null || echo unknown)"
echo "  DEBUG: uname=$(uname -m 2>/dev/null || echo unknown)"
echo "  DEBUG: opm=$(command -v opm 2>/dev/null || echo 'NOT FOUND')"
if command -v opm &>/dev/null; then
    echo "  DEBUG: opm version=$(opm version 2>&1 | head -1)"
    echo "  DEBUG: opm file type=$(file "$(command -v opm)" 2>/dev/null | head -1)"
fi
echo "  DEBUG: policy.json exists=$(test -f /etc/containers/policy.json && echo YES || echo NO)"
echo "  DEBUG: memory=$(cat /proc/meminfo 2>/dev/null | grep MemAvailable | head -1 || echo 'N/A')"

setup_registry_auth "${managed_secrets_yaml}" || {
    echo "🔴 Cannot set up registry credentials — unable to verify published index"
    exit 1
}

failures=0

if command -v opm &>/dev/null; then
    rendered=$(opm_render_cached "${target_index}") || exit 1

    line_count=$(wc -l < "${rendered}")
    echo "✅ opm render succeeded (${line_count} lines)"

    package_count=$(jq -r 'select(.schema == "olm.package") | .name' "${rendered}" 2>/dev/null | sort -u | wc -l)
    bundle_count=$(jq -r 'select(.schema == "olm.bundle") | .name' "${rendered}" 2>/dev/null | sort -u | wc -l)
    channel_count=$(jq -r 'select(.schema == "olm.channel") | .name' "${rendered}" 2>/dev/null | sort -u | wc -l)

    if [ "${package_count}" -ge 1 ]; then
        echo "✅ Found ${package_count} olm.package(s)"
    else
        echo "🔴 No olm.package entries found in published index"
        failures=$((failures + 1))
    fi

    if [ "${bundle_count}" -ge 1 ]; then
        echo "✅ Found ${bundle_count} olm.bundle(s)"
    else
        echo "🔴 No olm.bundle entries found in published index"
        failures=$((failures + 1))
    fi

    if [ "${channel_count}" -ge 1 ]; then
        echo "✅ Found ${channel_count} olm.channel(s)"
    else
        echo "🔴 No olm.channel entries found in published index"
        failures=$((failures + 1))
    fi

    # Cross-check: verify the fragment's packages appear in the published index.
    # This is informational — the published index tag may be overwritten by
    # concurrent IIB builds, so the test fragment's package is not guaranteed
    # to be present in the final tag at read time.
    if fragment_rendered=$(opm_render_cached "${fbc_fragment}"); then
        fragment_packages=$(jq -r 'select(.schema == "olm.package") | .name' "${fragment_rendered}" 2>/dev/null | sort -u)
        if [ -n "${fragment_packages}" ]; then
            while IFS= read -r pkg; do
                if jq -r 'select(.schema == "olm.package") | .name' "${rendered}" 2>/dev/null | grep -qx "${pkg}"; then
                    echo "✅ Fragment package '${pkg}' found in published index"
                else
                    echo "⚠️  Fragment package '${pkg}' not found in published index (may be due to concurrent IIB builds)"
                fi
            done <<< "${fragment_packages}"
        fi
    else
        echo "⚠️  Could not render fragment to cross-check packages (non-fatal)"
    fi

elif command -v skopeo &>/dev/null; then
    echo "⚠️  opm not available, falling back to skopeo inspect"
    if skopeo inspect --tls-verify=true "docker://${target_index}" &>/dev/null; then
        echo "✅ Published index image is pullable (skopeo inspect passed)"
    else
        echo "🔴 Published index image is NOT pullable"
        failures=$((failures + 1))
    fi
else
    echo "🔴 Neither opm nor skopeo available — cannot verify"
    exit 1
fi

if [ "${failures}" -gt 0 ]; then
    echo "🔴 Index content verification failed (${failures} assertion(s) failed)"
    exit 1
fi

echo "✅ Published index content verification passed"
exit 0
