#!/usr/bin/env bash
#
# generate-large-snapshot.sh - Utility to generate a large snapshot manifest
#
# Creates a Snapshot CR with approximately 200 components for testing the
# rh-advisories pipeline.
#
# Usage:
#   FRESH_BUILDS_FILE=/tmp/fresh-images-pool.txt \
#     ./generate-large-snapshot.sh <snapshot-name> <application-name> <namespace>
#
# Arguments:
#   snapshot-name      : Name for the snapshot
#   application-name   : Name of the application
#   namespace          : Kubernetes namespace
#
# Environment:
#   FRESH_BUILDS_FILE  : Path to image pool file (REQUIRED)
#
# Output:
#   Writes snapshot YAML to stdout
#

set -euo pipefail
set -E

# ─── Failure context tracking ────────────────────────────────────────────────
_FAILURE_CONTEXT_FILE="/tmp/generate-snapshot-error.txt"
_CURRENT_STEP="init"
_CURRENT_INDEX="?"
_CURRENT_IMAGE="(not started)"

_on_generate_error() {
    local err=$1 line=$2 cmd="$3"
    {
        printf 'generate-large-snapshot.sh failed\n'
        printf '  Component : [%s] %s\n' "${_CURRENT_INDEX}" "${_CURRENT_IMAGE}"
        printf '  Step      : %s\n'      "${_CURRENT_STEP}"
        printf '  Command   : %s\n'      "${cmd}"
        printf '  Line      : %s\n'      "${line}"
        printf '  Exit code : %s\n'      "${err}"
    } > "${_FAILURE_CONTEXT_FILE}"
    printf '❌ generate-large-snapshot.sh FAILED\n' >&2
    printf '   Component : [%s] %s\n' "${_CURRENT_INDEX}" "${_CURRENT_IMAGE}" >&2
    printf '   Step      : %s\n'     "${_CURRENT_STEP}" >&2
    printf '   Command   : %s\n'     "${cmd}" >&2
    printf '   Line      : %s  (exit %s)\n' "${line}" "${err}" >&2
}
trap '_on_generate_error $? $LINENO "$BASH_COMMAND"' ERR

SNAPSHOT_NAME="${1:-large-snapshot}"
APPLICATION_NAME="${2:-test-app}"
NAMESPACE="${3:-dev-release-team-tenant}"

# ============================================================================
# IMAGE STRATEGY: Consume an Image List Only
# ============================================================================
#
# This generator consumes an image list file and produces a Snapshot manifest.
# It does not build images or validate them against the registry.
#
# ============================================================================

# Configuration
FRESH_BUILDS_FILE="${FRESH_BUILDS_FILE:-/tmp/fresh-images-pool.txt}"

# Verify fresh builds file exists
if [ -z "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: FRESH_BUILDS_FILE environment variable not set" >&2
    echo "" >&2
    echo "Provide a file containing component names or image references." >&2
    echo "" >&2
    exit 1
fi

if [ ! -f "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: Fresh builds file not found: ${FRESH_BUILDS_FILE}" >&2
    echo "" >&2
    echo "Provide a valid file path in FRESH_BUILDS_FILE." >&2
    echo "" >&2
    exit 1
fi

# Read image pool from fresh builds file
declare -a IMAGE_POOL=()
while IFS= read -r line; do
    # Allow comments/blank lines in static lists
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -z "${line}" ] && continue

    IMAGE_POOL+=("${line}")
done < "${FRESH_BUILDS_FILE}"

COMPONENT_COUNT=${#IMAGE_POOL[@]}

if [ "${COMPONENT_COUNT}" -eq 0 ]; then
    echo "❌ Error: No images found in ${FRESH_BUILDS_FILE}" >&2
    exit 1
fi

echo "📦 Using image pool: ${FRESH_BUILDS_FILE} (${COMPONENT_COUNT} images)" >&2

# ============================================================================
# Helper Functions
# ============================================================================

# Resolve an image pool entry to a full image reference.
# Pool entries are already full refs (e.g. quay.io/…/repo:tag), so this
# function is a pass-through. It exists as a named hook so callers remain
# readable and the step label in error output is meaningful.
resolve_container_image() {
    echo "$1"
}

extract_component_name() {
    local image_ref="$1"
    local name="${image_ref##*/}"   # after last /
    name="${name%%@*}"              # strip @sha256...
    name="${name%%:*}"              # strip :tag
    echo "${name}"
}

echo "Generating large snapshot with ${COMPONENT_COUNT} components..." >&2
echo "" >&2

# ============================================================================
# TAG RESOLUTION: Resolve :stable tags to @sha256: digests
# ============================================================================
#
# When using static image pools with :stable tags, we need to resolve them to
# concrete digests before creating the snapshot. This ensures:
# 1. Snapshot references immutable image versions
# 2. Release pipeline gets consistent image references
# 3. Attestations can be properly matched to images
#
# Resolution strategy:
# - Use skopeo inspect (fastest, works with any registry)
# - Fallback to Quay API if skopeo not available
# ============================================================================

resolve_tag_to_digest() {
    local image_ref="$1"

    # Skip if already a digest reference or no tag separator
    if [[ "${image_ref}" == *"@sha256:"* ]] || [[ "${image_ref}" != *":"* ]]; then
        echo "${image_ref}"
        return 0
    fi

    local attempt
    for attempt in 1 2 3; do
        [ "${attempt}" -gt 1 ] && sleep $(( attempt * 3 ))

        # Try skopeo first (fastest and most reliable).
        # --retry-times 3 handles transient registry errors within each attempt.
        if command -v skopeo &>/dev/null; then
            local digest
            local repo="${image_ref%:*}"  # Strip :tag

            if digest=$(skopeo inspect --retry-times 3 --format '{{.Digest}}' \
                    "docker://${image_ref}" 2>/dev/null); then
                echo "${repo}@${digest}"
                return 0
            fi
        fi

        # Fallback: Try Quay API
        if [[ "${image_ref}" == *"quay.io"* ]]; then
            local repo_path="${image_ref#quay.io/}"
            local repo="${repo_path%:*}"
            local tag="${repo_path##*:}"

            local api_url="https://quay.io/api/v1/repository/${repo}/tag/${tag}"
            local manifest_digest
            if manifest_digest=$(curl -sf --retry 3 --retry-delay 5 \
                    "${api_url}" 2>/dev/null \
                    | jq -r '.manifest_digest // empty' 2>/dev/null) \
                    && [ -n "${manifest_digest}" ]; then
                echo "quay.io/${repo}@${manifest_digest}"
                return 0
            fi
        fi

        echo "⚠️  resolve_tag_to_digest: attempt ${attempt}/3 failed for ${image_ref}" >&2
    done

    echo "❌ Error: Could not resolve tag to digest: ${image_ref}" >&2
    return 1
}

echo "🔍 Resolving image references..." >&2

declare -a RESOLVED_IMAGES=()

for (( i=0; i<COMPONENT_COUNT && i<${#IMAGE_POOL[@]}; i++ )); do
    image_entry="${IMAGE_POOL[$i]}"
    _CURRENT_INDEX=$i
    _CURRENT_IMAGE="${image_entry}"
    _CURRENT_STEP="resolve-container-image"

    image_ref="$(resolve_container_image "${image_entry}")"

    _CURRENT_STEP="resolve-tag-to-digest"
    resolved_image="$(resolve_tag_to_digest "${image_ref}")"

    RESOLVED_IMAGES+=("${resolved_image}")

    if [ $((i % 20)) -eq 0 ] && [ $i -gt 0 ]; then
        echo "   Resolved ${i}/${COMPONENT_COUNT} images..." >&2
    fi
done

echo "" >&2
echo "   ✅ Processed ${#RESOLVED_IMAGES[@]} images" >&2
echo "" >&2

cat <<EOF
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Snapshot
metadata:
  name: "${SNAPSHOT_NAME}"
  namespace: "${NAMESPACE}"
  labels:
    test.appstudio.openshift.io/type: "large-snapshot"
    test.appstudio.openshift.io/component-count: "${COMPONENT_COUNT}"
    appstudio.openshift.io/application: "${APPLICATION_NAME}"
  annotations:
    test.appstudio.openshift.io/description: "Large snapshot with ${COMPONENT_COUNT} components for rh-advisories pipeline testing (using actual component names from images)"
    test.appstudio.openshift.io/available-images: "${COMPONENT_COUNT}"
    # Skip build since we're using pre-built container images
    test.appstudio.openshift.io/skip-build: "true"
    # Skip idempotency to allow re-testing with the same snapshot data
    # Expected behavior: Release can proceed even if this exact snapshot was released before
    # Rationale: This is a test snapshot with static pre-built images for scale testing
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  application: "${APPLICATION_NAME}"
  displayName: "Large Snapshot - ${COMPONENT_COUNT} Components"
  displayDescription: "Test snapshot with ${COMPONENT_COUNT} components using actual component names for large-scale release testing"
  artifacts: {}
  components:
EOF

for (( i=1; i<=COMPONENT_COUNT; i++ )); do
    # Use resolved images (tags converted to digests)
    IMAGE_INDEX=$(((i - 1) % ${#RESOLVED_IMAGES[@]}))
    CONTAINER_IMAGE="${RESOLVED_IMAGES[$IMAGE_INDEX]}"

    # Extract actual component name from image URL
    COMPONENT_NAME="$(extract_component_name "${CONTAINER_IMAGE}")"

    # Use the actual source repository that components were built from
    # This matches the attestations created during PAC builds
    SOURCE_URL="https://github.com/hacbs-release-tests/e2e-base"

    cat <<EOF
    - name: "${COMPONENT_NAME}"
      containerImage: "${CONTAINER_IMAGE}"
      source:
        git:
          url: "${SOURCE_URL}"
          revision: "main"
EOF
done

echo "" >&2
echo "✅ Snapshot manifest generated successfully" >&2
echo "   Snapshot name: ${SNAPSHOT_NAME}" >&2
echo "   Application: ${APPLICATION_NAME}" >&2
echo "   Namespace: ${NAMESPACE}" >&2
echo "   Components: ${COMPONENT_COUNT}" >&2
echo "" >&2
echo "To apply this snapshot:" >&2
echo "  ./generate-large-snapshot.sh ${SNAPSHOT_NAME} ${APPLICATION_NAME} ${NAMESPACE} ${COMPONENT_COUNT} | kubectl apply -f -" >&2
