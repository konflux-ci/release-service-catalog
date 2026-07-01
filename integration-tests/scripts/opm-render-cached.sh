#!/usr/bin/env bash
# Shared helper to render an FBC image with opm and cache the result.
#
# Renders the image once and stores the output in a cache directory.
# Subsequent calls with the same image return the cached file path.
#
# Usage:
#   source opm-render-cached.sh
#
# Functions:
#   init_render_cache <cache_dir>
#     Initializes the cache directory. Must be called before opm_render_cached.
#     The caller controls where the cache lives for predictability.
#
#   setup_registry_auth <managed_secrets_yaml>
#     Sets up DOCKER_CONFIG from fbc-preview-index-image-pull-secret.
#     Call once before any opm_render_cached calls.
#
#   opm_render_cached <image_ref>
#     Renders the image (or returns cached output).
#     Prints the path to the rendered file on stdout.
#     Returns 0 on success, 1 on failure.
#
#   cleanup_render_cache
#     Removes auth credentials. The caller owns the cache directory lifecycle.
#     Call in a trap or at the end of your script.

_OPM_RENDER_CACHE_DIR=""
_OPM_RENDER_AUTH_DIR=""

init_render_cache() {
    local cache_dir="${1:?Usage: init_render_cache <cache_dir>}"
    mkdir -p "${cache_dir}"
    _OPM_RENDER_CACHE_DIR="${cache_dir}"
}

setup_registry_auth() {
    local secrets_file="${1:?Usage: setup_registry_auth <managed_secrets_yaml>}"

    if [ ! -f "${secrets_file}" ]; then
        echo "🔴 Secrets file not found: ${secrets_file}" >&2
        return 1
    fi

    _OPM_RENDER_AUTH_DIR=$(mktemp -d)

    local selectors=("fbc-preview-index-image-pull-secret" "fbc-preview-index-image-pull")
    for selector in "${selectors[@]}"; do
        local dockercfg
        dockercfg=$(yq ". | select(.metadata.name | contains(\"${selector}\")) | .data.\".dockerconfigjson\"" \
            "${secrets_file}" 2>/dev/null)

        if [ -n "${dockercfg}" ] && [ "${dockercfg}" != "null" ]; then
            echo "${dockercfg}" | base64 -d > "${_OPM_RENDER_AUTH_DIR}/config.json" 2>/dev/null
            if [ -s "${_OPM_RENDER_AUTH_DIR}/config.json" ]; then
                export DOCKER_CONFIG="${_OPM_RENDER_AUTH_DIR}"
                echo "✅ Registry credentials configured (${selector})"
                return 0
            fi
        fi
    done

    echo "🔴 No valid registry credentials found in ${secrets_file}" >&2
    rm -rf "${_OPM_RENDER_AUTH_DIR}"
    _OPM_RENDER_AUTH_DIR=""
    return 1
}

opm_render_cached() {
    local image_ref="${1:?Usage: opm_render_cached <image_ref>}"

    if ! command -v opm &>/dev/null; then
        echo "🔴 opm not available" >&2
        return 1
    fi

    if [ -z "${_OPM_RENDER_CACHE_DIR}" ]; then
        echo "🔴 Cache not initialized — call init_render_cache first" >&2
        return 1
    fi

    local cache_key
    cache_key=$(echo -n "${image_ref}" | md5sum | cut -d' ' -f1)
    local cache_file="${_OPM_RENDER_CACHE_DIR}/${cache_key}.json"

    if [ -f "${cache_file}" ]; then
        echo "${cache_file}"
        return 0
    fi

    echo "  Rendering: ${image_ref}..." >&2
    echo "  DEBUG: opm path=$(command -v opm) version=$(opm version 2>&1 | head -1)" >&2
    echo "  DEBUG: DOCKER_CONFIG=${DOCKER_CONFIG:-unset}" >&2
    echo "  DEBUG: cache_file=${cache_file}" >&2
    if [ -n "${DOCKER_CONFIG:-}" ] && [ -f "${DOCKER_CONFIG}/config.json" ]; then
        echo "  DEBUG: config.json exists ($(wc -c < "${DOCKER_CONFIG}/config.json") bytes)" >&2
    else
        echo "  DEBUG: config.json NOT found at ${DOCKER_CONFIG:-unset}/config.json" >&2
    fi

    opm render "${image_ref}" > "${cache_file}" 2>&1
    local opm_exit=$?

    if [ $opm_exit -ne 0 ]; then
        echo "🔴 opm render failed for: ${image_ref} (exit code: ${opm_exit})" >&2
        if [ $opm_exit -gt 128 ]; then
            echo "  Killed by signal: $((opm_exit - 128)) (e.g. 9=SIGKILL/OOM, 11=SIGSEGV)" >&2
        fi
        local file_size=0
        if [ -f "${cache_file}" ]; then
            file_size=$(wc -c < "${cache_file}")
        fi
        echo "  Cache file size: ${file_size} bytes" >&2
        echo "  Error (first 10 lines):" >&2
        head -10 "${cache_file}" | sed 's/^/    /' >&2
        rm -f "${cache_file}"
        return 1
    fi

    local line_count
    line_count=$(wc -l < "${cache_file}")
    echo "  Rendered ${line_count} lines (cached)" >&2

    echo "${cache_file}"
    return 0
}

cleanup_render_cache() {
    if [ -n "${_OPM_RENDER_AUTH_DIR}" ]; then
        rm -rf "${_OPM_RENDER_AUTH_DIR}"
        _OPM_RENDER_AUTH_DIR=""
        unset DOCKER_CONFIG
    fi
}
