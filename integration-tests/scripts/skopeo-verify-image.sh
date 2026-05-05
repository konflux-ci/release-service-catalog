#!/usr/bin/env bash
# Verifies that an image is pullable from its target registry using skopeo.
#
# Usage: skopeo-verify-image.sh <image_url> <image_shasum> <managed_secrets_yaml> [arches]
#
# Arguments:
#   image_url            - The published image URL (may include a tag or digest)
#   image_shasum         - The image digest (e.g. sha256:abc123...)
#   managed_secrets_yaml - Path to the decrypted managed-secrets.yaml file
#   arches (optional)    - Space-separated list of GOARCH values (e.g. "amd64 arm64").
#                          When set, verifies the digest is an OCI image index or Docker
#                          manifest list (--raw mediaType), then runs skopeo inspect with
#                          --override-arch for each arch. On failure, re-runs the failing
#                          inspect without suppressing stderr so logs stay debuggable.
#
# Environment:
#   SKOPEO_RETRY_TIMES - skopeo --retry-times value (default: 3). Override in CI/local:
#                        export SKOPEO_RETRY_TIMES=5
#
# Exits with 0 on success, 1 on failure.

set -euo pipefail

SKOPEO_RETRY_TIMES="${SKOPEO_RETRY_TIMES:-3}"

image_url="${1:?image_url argument is required}"
image_shasum="${2:?image_shasum argument is required}"
managed_secrets_yaml="${3:?managed_secrets_yaml argument is required}"
optional_arches="${4:-}"

STRIPPED_PULLSPEC="${image_url}"
if [[ "${STRIPPED_PULLSPEC}" == *"@"* ]]; then
    STRIPPED_PULLSPEC="${STRIPPED_PULLSPEC%@*}"
    echo "Stripped digest from: ${image_url} -> ${STRIPPED_PULLSPEC}"
fi

# Tags appear only after the last '/'; registry ports (host:port) must not be stripped.
if [[ "${STRIPPED_PULLSPEC}" == */* ]]; then
    path_prefix="${STRIPPED_PULLSPEC%/*}"
    final_segment="${STRIPPED_PULLSPEC##*/}"
else
    path_prefix=""
    final_segment="${STRIPPED_PULLSPEC}"
fi
if [[ "${final_segment}" == *":"* ]]; then
    final_segment="${final_segment%:*}"
    if [[ -n "${path_prefix}" ]]; then
        STRIPPED_PULLSPEC="${path_prefix}/${final_segment}"
    else
        STRIPPED_PULLSPEC="${final_segment}"
    fi
    echo "Stripped tag from: ${image_url} -> ${STRIPPED_PULLSPEC}"
elif [[ "${STRIPPED_PULLSPEC}" == "${image_url}" ]]; then
    echo "No tag or digest found, using original as is: ${STRIPPED_PULLSPEC}"
fi

COMPLETE_PULLSPEC="${STRIPPED_PULLSPEC}@${image_shasum}"
echo "New complete pullspec: ${COMPLETE_PULLSPEC}"

# CI often runs scripts under xtrace (bash -x). Disable tracing while loading registry credentials.
xtrace_was_on=0
case $- in
  *x*) xtrace_was_on=1 ;;
esac
if [ "${xtrace_was_on}" -eq 1 ]; then
  set +x
fi

DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
cleanup_skopeo_verify() {
  if [ "${xtrace_was_on}" -eq 1 ]; then
    set -x
  fi
  rm -rf "${DOCKER_CONFIG}"
}
trap cleanup_skopeo_verify EXIT

dockerconfig_b64="$(
  yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
    "${managed_secrets_yaml}" | head -n 1
)"
if [[ -z "${dockerconfig_b64}" || "${dockerconfig_b64}" == "null" ]]; then
  echo "🔴 Failed to find push-* dockerconfigjson in managed secrets."
  exit 1
fi
printf '%s' "${dockerconfig_b64}" | base64 -d > "${DOCKER_CONFIG}/config.json"
unset dockerconfig_b64

if [[ -n "${optional_arches}" ]]; then
    set +e
    raw_manifest="$(skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" --raw "docker://${COMPLETE_PULLSPEC}" 2>/dev/null)"
    rc=$?
    set -e
    if [[ "${rc}" -ne 0 ]]; then
      echo "🔴 Failed to fetch raw manifest for '${COMPLETE_PULLSPEC}'."
      skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" --raw "docker://${COMPLETE_PULLSPEC}"
      exit 1
    fi

    if ! media_type="$(jq -r '.mediaType // empty' <<< "${raw_manifest}")" || [[ -z "${media_type}" ]]; then
      echo "🔴 Unable to determine manifest mediaType from raw inspect output."
      echo "Raw manifest (first 200 chars): $(head -c 200 <<< "${raw_manifest}")"
      exit 1
    fi
    if [[ "${media_type}" != "application/vnd.oci.image.index.v1+json" ]] &&
       [[ "${media_type}" != "application/vnd.docker.distribution.manifest.list.v2+json" ]]; then
        echo "🔴 Expected OCI image index or Docker manifest list, found mediaType: '${media_type}'"
        exit 1
    fi
    echo "✅️ Verified multi-arch index (mediaType: ${media_type})."

    for arch in ${optional_arches}; do
        if skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" --override-arch "${arch}" "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
            echo "✅️ Image '${COMPLETE_PULLSPEC}' can be inspected for arch ${arch}."
        else
            echo "🔴 Failed skopeo inspect for arch ${arch} on '${COMPLETE_PULLSPEC}'."
            skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" --override-arch "${arch}" "docker://${COMPLETE_PULLSPEC}"
            exit 1
        fi
    done
elif skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
    echo "✅️ Image '${COMPLETE_PULLSPEC}' can be pulled using skopeo."
else
    echo "🔴 Failed to pull or inspect image '${COMPLETE_PULLSPEC}'."
    skopeo inspect --tls-verify=true --retry-times "${SKOPEO_RETRY_TIMES}" "docker://${COMPLETE_PULLSPEC}"
    exit 1
fi
