#!/bin/bash
set -euo pipefail

#
# generate-image-pool.sh - Generate a pool of public images for testing
#
# This script generates a list of unique public container images from quay.io
# that can be used for large-scale release pipeline testing.
#
# Output: Prints image references (one per line) to stdout
#         All status messages go to stderr
#
# Usage:
#   ./generate-image-pool.sh [count]
#
# Arguments:
#   count: Number of images to generate (default: 200)
#

COUNT="${1:-200}"

echo>&2 "🎯 Generating $COUNT public images..."

# Base pool of verified public Quay.io images
# These are known-good images from konflux-ci and other public namespaces
KONFLUX_IMAGES=(
    "quay.io/konflux-ci/oras:latest"
    "quay.io/konflux-ci/release-service-utils:latest"
    "quay.io/konflux-ci/appstudio-utils:latest"
    "quay.io/konflux-ci/yq:latest"
    "quay.io/konflux-ci/konflux-test:latest"
    "quay.io/redhat-appstudio/ec-task-bundle:latest"
    "quay.io/redhat-appstudio/ec-cli:latest"
    "quay.io/redhat-appstudio/application-service:latest"
    "quay.io/redhat-appstudio/spi-oauth:latest"
    "quay.io/redhat-appstudio/enterprise-contract-controller:latest"
)

# Additional verified images
OTHER_IMAGES=(
    "quay.io/fedora/fedora:latest"
    "quay.io/centos/centos:stream9"
    "quay.io/buildah/stable:latest"
    "quay.io/containers/podman:latest"
    "quay.io/quay/redis:latest"
    "quay.io/prometheus/prometheus:latest"
    "quay.io/prometheus/node-exporter:latest"
    "quay.io/prometheus/alertmanager:latest"
    "quay.io/coreos/etcd:latest"
    "quay.io/skopeo/stable:latest"
)

# Combine all images
ALL_IMAGES=("${KONFLUX_IMAGES[@]}" "${OTHER_IMAGES[@]}")

# Output images, cycling through the pool to reach the requested count
generated=0
while [ $generated -lt "$COUNT" ]; do
    for image in "${ALL_IMAGES[@]}"; do
        if [ $generated -ge "$COUNT" ]; then
            break
        fi
        # Add a unique suffix to make each image distinct for testing
        # This allows us to cycle through the base images multiple times
        echo "${image}@$(echo -n "${image}-${generated}" | sha256sum | awk '{print $1}')"
        ((generated++))
    done
done

echo>&2 "✅ Generated $generated images"
