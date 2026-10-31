#!/usr/bin/env bash
# Load dockerconfig for quay.io/konflux-ci/release-service-trusted-artifacts.
#
# The in-cluster PipelineRun already authenticates via the managed SA secret
# applied from ansible-vault (managed-secrets.yaml). Local oras/skopeo on the
# e2e runner do not, so blob fetches 401 once the repo is private.
#
# Usage (source this file, then):
#   setup_trusted_artifacts_docker_config <namespace> [service_account]
#   oras blob fetch --registry-config "${TRUSTED_ARTIFACTS_REGISTRY_CONFIG}" ...
#   cleanup_trusted_artifacts_docker_config
#
# Discovery order for the dockerconfigjson:
#   1. Cluster secret on the managed SA (imagePullSecrets / secrets)
#   2. Any trusted-artifacts dockerconfig secret in the namespace
#   3. Decrypted managed-secrets.yaml (MANAGED_SECRETS_YAML or SUITE_DIR)
#
# Do not trap EXIT here: run-test.sh already owns EXIT for suite cleanup.

_TA_DOCKER_CONFIG_DIR=""
TRUSTED_ARTIFACTS_REGISTRY_CONFIG=""

_ta_disable_xtrace() {
    _TA_XTRACE_WAS_ON=0
    case $- in
        *x*) _TA_XTRACE_WAS_ON=1 ;;
    esac
    if [ "${_TA_XTRACE_WAS_ON}" -eq 1 ]; then
        set +x
    fi
}

_ta_restore_xtrace() {
    if [ "${_TA_XTRACE_WAS_ON:-0}" -eq 1 ]; then
        set -x
    fi
}

_ta_secret_name_from_sa() {
    local namespace="$1"
    local sa_name="$2"

    kubectl get sa "${sa_name}" -n "${namespace}" -o json 2>/dev/null | jq -r '
        ((.imagePullSecrets // []) + (.secrets // []))
        | .[].name
        | select(test("trusted-artifacts-pull-secret"))
    ' 2>/dev/null | head -n 1 || true
}

_ta_secret_name_from_namespace() {
    local namespace="$1"

    kubectl get secrets -n "${namespace}" -o json 2>/dev/null | jq -r '
        .items[]
        | select(.type == "kubernetes.io/dockerconfigjson")
        | .metadata.name
        | select(test("trusted-artifacts-pull-secret"))
    ' 2>/dev/null | head -n 1 || true
}

_ta_dockerconfig_b64_from_secret() {
    local namespace="$1"
    local secret_name="$2"

    kubectl get secret "${secret_name}" -n "${namespace}" -o json 2>/dev/null \
        | jq -r '.data[".dockerconfigjson"] // empty' 2>/dev/null || true
}

_ta_dockerconfig_b64_from_yaml() {
    local yaml_path="$1"

    if [ ! -f "${yaml_path}" ]; then
        return 0
    fi
    yq '. | select(.metadata.name | test("trusted-artifacts-pull-secret")) | .data.".dockerconfigjson"' \
        "${yaml_path}" 2>/dev/null | head -n 1 || true
}

_ta_managed_secrets_yaml_path() {
    if [ -n "${MANAGED_SECRETS_YAML:-}" ]; then
        printf '%s' "${MANAGED_SECRETS_YAML}"
        return 0
    fi
    if [ -n "${SUITE_DIR:-}" ]; then
        printf '%s/resources/managed/secrets/managed-secrets.yaml' "${SUITE_DIR}"
        return 0
    fi
    return 1
}

cleanup_trusted_artifacts_docker_config() {
    if [ -n "${_TA_DOCKER_CONFIG_DIR:-}" ]; then
        rm -rf "${_TA_DOCKER_CONFIG_DIR}"
        _TA_DOCKER_CONFIG_DIR=""
    fi
    TRUSTED_ARTIFACTS_REGISTRY_CONFIG=""
    unset DOCKER_CONFIG
}

# setup_trusted_artifacts_docker_config <namespace> [service_account]
setup_trusted_artifacts_docker_config() {
    local namespace="${1:-}"
    local sa_name="${2:-}"
    local secret_name=""
    local dockerconfig_b64=""
    local source_desc=""
    local yaml_path=""

    if [ -z "${namespace}" ]; then
        echo "🔴 setup_trusted_artifacts_docker_config: namespace is required" >&2
        return 1
    fi

    cleanup_trusted_artifacts_docker_config

    if [ -n "${sa_name}" ]; then
        secret_name="$(_ta_secret_name_from_sa "${namespace}" "${sa_name}")"
    fi
    if [ -z "${secret_name}" ]; then
        secret_name="$(_ta_secret_name_from_namespace "${namespace}")"
    fi
    if [ -n "${secret_name}" ]; then
        dockerconfig_b64="$(_ta_dockerconfig_b64_from_secret "${namespace}" "${secret_name}")"
        source_desc="cluster secret ${secret_name}"
    fi

    if [ -z "${dockerconfig_b64}" ] || [ "${dockerconfig_b64}" = "null" ]; then
        if yaml_path="$(_ta_managed_secrets_yaml_path)"; then
            dockerconfig_b64="$(_ta_dockerconfig_b64_from_yaml "${yaml_path}")"
            source_desc="managed-secrets.yaml ${yaml_path}"
        fi
    fi

    if [ -z "${dockerconfig_b64}" ] || [ "${dockerconfig_b64}" = "null" ]; then
        echo "🔴 Could not find trusted-artifacts dockerconfig in namespace ${namespace}" >&2
        echo "   Expected SA secret konflux-ci-konflux-release-trusted-artifacts-pull-secret-*" >&2
        return 1
    fi

    _ta_disable_xtrace
    _TA_DOCKER_CONFIG_DIR="$(mktemp -d)"
    if ! printf '%s' "${dockerconfig_b64}" | base64 -d > "${_TA_DOCKER_CONFIG_DIR}/config.json"; then
        _ta_restore_xtrace
        rm -rf "${_TA_DOCKER_CONFIG_DIR}"
        _TA_DOCKER_CONFIG_DIR=""
        echo "🔴 Failed to decode trusted-artifacts dockerconfigjson" >&2
        return 1
    fi
    unset dockerconfig_b64
    if [ ! -s "${_TA_DOCKER_CONFIG_DIR}/config.json" ]; then
        _ta_restore_xtrace
        rm -rf "${_TA_DOCKER_CONFIG_DIR}"
        _TA_DOCKER_CONFIG_DIR=""
        echo "🔴 Decoded trusted-artifacts dockerconfigjson is empty" >&2
        return 1
    fi
    ln -s "${_TA_DOCKER_CONFIG_DIR}/config.json" "${_TA_DOCKER_CONFIG_DIR}/auth.json"
    export DOCKER_CONFIG="${_TA_DOCKER_CONFIG_DIR}"
    TRUSTED_ARTIFACTS_REGISTRY_CONFIG="${_TA_DOCKER_CONFIG_DIR}/config.json"
    export TRUSTED_ARTIFACTS_REGISTRY_CONFIG
    _ta_restore_xtrace

    echo "✅ Trusted-artifacts registry auth configured from ${source_desc}" >&2
}
