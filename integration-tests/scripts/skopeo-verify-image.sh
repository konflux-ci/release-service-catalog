#!/usr/bin/env bash
# Verifies that an image is pullable from its target registry using skopeo.
#
# Usage: skopeo-verify-image.sh <image_url> <image_shasum> <managed_secrets_yaml>
#
# Arguments:
#   image_url            - The published image URL (may include a tag or digest)
#   image_shasum         - The image digest (e.g. sha256:abc123...)
#   managed_secrets_yaml - Path to the decrypted managed-secrets.yaml file
#
# Exits with 0 on success, 1 on failure.

set -euo pipefail

image_url="${1:?image_url argument is required}"
image_shasum="${2:?image_shasum argument is required}"
managed_secrets_yaml="${3:?managed_secrets_yaml argument is required}"

if [[ "${image_url}" == *"@"* ]]; then
    STRIPPED_PULLSPEC="${image_url%@*}"
    echo "Stripped digest from: ${image_url} -> ${STRIPPED_PULLSPEC}"
elif [[ "${image_url}" == *":"* ]]; then
    STRIPPED_PULLSPEC="${image_url%:*}"
    echo "Stripped tag from: ${image_url} -> ${STRIPPED_PULLSPEC}"
else
    STRIPPED_PULLSPEC="${image_url}"
    echo "No tag or digest found, using original as is: ${STRIPPED_PULLSPEC}"
fi

COMPLETE_PULLSPEC="${STRIPPED_PULLSPEC}@${image_shasum}"
echo "New complete pullspec: ${COMPLETE_PULLSPEC}"

DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG

yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
    "${managed_secrets_yaml}" | base64 -d > "${DOCKER_CONFIG}/config.json"

if skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
    echo "✅️ Image '${COMPLETE_PULLSPEC}' can be pulled using skopeo."
else
    echo "🔴 Failed to pull or inspect image '${COMPLETE_PULLSPEC}'."
    skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}"
    exit 1
fi
