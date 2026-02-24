#!/usr/bin/env bash
#
# generate-large-snapshot.sh - Utility to generate a large snapshot manifest
#
# This script creates a Snapshot CR with approximately 200 components
# for testing the rh-advisories pipeline with worst-case signing performance.
#
# REQUIRES: Fresh Konflux builds (unsigned images)
#   Run: ./test.sh (builds + tests)
#
# Usage:
#   FRESH_BUILDS_FILE=/tmp/fresh-images-pool.txt \
#     ./generate-large-snapshot.sh <snapshot-name> <application-name> <namespace> [component-count]
#
# Arguments:
#   snapshot-name      : Name for the snapshot
#   application-name   : Name of the application
#   namespace          : Kubernetes namespace
#   component-count    : Number of components (default: 200)
#
# Environment:
#   FRESH_BUILDS_FILE       : Path to fresh builds file (REQUIRED)
#   ENABLE_DIGEST_MUTATION  : Mutate image digests for worst-case Pyxis signing (default: false)
#   DIGEST_MUTATION_RUN_ID  : Unique run ID used as mutation label/tag (default: timestamp)
#   MANAGED_NAMESPACE       : Namespace where the generated EC public key secret is stored
#                             (default: same as image namespace)
#
# Push credentials for mutation are read automatically from imagerepository push secrets
# (imagerepository-for-large-snapshot-build-*-image-push) in the tenant namespace.
# These per-component secrets have write access to quay.io/redhat-user-workloads-stage
# and are created by Konflux ImageRepository CRs when components are set up.
#
# Output:
#   Writes snapshot YAML to stdout
#
# Example:
#   export FRESH_BUILDS_FILE=/tmp/fresh-images-pool.txt
#   ./generate-large-snapshot.sh my-snapshot my-app dev-tenant 200 > snapshot.yaml
#   kubectl apply -f snapshot.yaml
#

set -euo pipefail

SNAPSHOT_NAME="${1:-large-snapshot}"
APPLICATION_NAME="${2:-test-app}"
NAMESPACE="${3:-dev-release-team-tenant}"
COMPONENT_COUNT="${4:-200}"

# ============================================================================
# Digest Mutation Configuration (for Pyxis Idempotency Avoidance)
# ============================================================================
# Enable digest mutation to force worst-case signing every run.
# Each run gets fresh digests so Pyxis never finds cached signatures.
ENABLE_DIGEST_MUTATION="${ENABLE_DIGEST_MUTATION:-false}"
DIGEST_MUTATION_RUN_ID="${DIGEST_MUTATION_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"


# ============================================================================
# Mutation Signing Configuration
# ============================================================================
# After every successful digest mutation, sign the new image and attach a SLSA
# provenance attestation using a freshly-generated cosign key pair.
# The public half is stored as secret EC_PUBKEY_SECRET_NAME in MANAGED_NAMESPACE so
# that the EC policy (publicKey: k8s://${managed_namespace}/${EC_PUBKEY_SECRET_NAME}) can
# verify it during verify-conforma.  There is NO fallback — any failure is fatal.
MANAGED_NAMESPACE="${MANAGED_NAMESPACE:-${NAMESPACE}}"

# Validate COMPONENT_COUNT is a positive integer
if ! [[ "${COMPONENT_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: COMPONENT_COUNT must be a positive integer (got: '${COMPONENT_COUNT}')" >&2
    exit 1
fi

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

POOL_SIZE=${#IMAGE_POOL[@]}

# Validate pool has images
if [ ${POOL_SIZE} -eq 0 ]; then
    echo "❌ Error: No images found in ${FRESH_BUILDS_FILE}" >&2
    echo "   The image pool file is empty or contains no valid images" >&2
    exit 1
fi

echo "📦 Using image pool file" >&2
echo "   Source: ${FRESH_BUILDS_FILE}" >&2
echo "   Entries: ${POOL_SIZE}" >&2

# Limit COMPONENT_COUNT to available images in pool
if [ ${COMPONENT_COUNT} -gt ${POOL_SIZE} ]; then
    echo "⚠️  Requested ${COMPONENT_COUNT} components but only ${POOL_SIZE} images available" >&2
    echo "   Limiting snapshot to ${POOL_SIZE} components" >&2
    COMPONENT_COUNT=${POOL_SIZE}
fi

# Also limit to 200 components for snapshot (even if more images available)
MAX_SNAPSHOT_COMPONENTS=200
ACTUAL_COMPONENT_COUNT=${COMPONENT_COUNT}
if [ ${COMPONENT_COUNT} -gt ${MAX_SNAPSHOT_COMPONENTS} ]; then
    echo "⚠️  Limiting snapshot to ${MAX_SNAPSHOT_COMPONENTS} components (found ${COMPONENT_COUNT} images)" >&2
    COMPONENT_COUNT=${MAX_SNAPSHOT_COMPONENTS}
fi

# ============================================================================
# Helper Functions (must be defined before resolution)
# ============================================================================

# Mutate an image to generate a new digest (for Pyxis idempotency avoidance).
#
# For manifest lists (multi-arch), mutates EACH platform image individually and
# re-assembles a new manifest list — preserving the full multi-arch structure.
# This ensures that rh-sign-image, rh-sign-image-cosign, and create-pyxis-image
# all process 4 arch digests per component (true worst-case load).
#
# Mutated images are pushed directly back to quay.io/redhat-user-workloads-stage
# using per-component imagerepository push secrets (write access confirmed).
#
# For single-arch images, falls back to plain crane mutate.
#
# Returns: dest_repo@sha256:NEW_INDEX_DIGEST  (the new manifest list digest)
mutate_image_digest() {
    local source_image="$1"
    local run_id="${2:-$(date +%s)}"
    local max_retries=3
    local retry_delay=2

    # Extract repo from source (handle both digest and tag refs)
    local repo
    if [[ "${source_image}" == *"@"* ]]; then
        repo="${source_image%@*}"
        if [[ "${repo}" == *":"* ]]; then
            repo="${repo%:*}"
        fi
    elif [[ "${source_image}" == *":"* ]]; then
        repo="${source_image%:*}"
    else
        repo="${source_image}"
    fi

    local dest_repo="${repo}"

    local mutated_tag="mutated-${run_id}"
    local dest_image="${dest_repo}:${mutated_tag}"
    local label_value="konflux-test-mutation-${run_id}"

    # Detect whether source is a manifest list (multi-arch index).
    # Docker manifest lists: mediaType = "application/vnd.docker.distribution.manifest.list.v2+json"
    # OCI image indexes:     mediaType = "application/vnd.oci.image.index.v1+json"
    #                        (some OCI indexes omit mediaType; check for .manifests[] instead)
    local raw_manifest media_type
    raw_manifest=$(skopeo inspect --raw \
        ${DOCKER_CONFIG:+--authfile "${DOCKER_CONFIG}/config.json"} \
        "docker://${source_image}" 2>/dev/null)
    media_type=$(echo "${raw_manifest}" | jq -r '.mediaType // ""' 2>/dev/null)

    local is_manifest_list=false
    if [[ "${media_type}" == *"manifest.list"* ]] || \
       [[ "${media_type}" == *"image.index"* ]] || \
       echo "${raw_manifest}" | jq -e '.manifests | length > 0' >/dev/null 2>&1; then
        is_manifest_list=true
    fi

    if [ "${is_manifest_list}" = "true" ]; then
        # ── Multi-arch path ───────────────────────────────────────────────────
        # Mutate each platform image individually, then re-assemble a new index.
        local platforms
        mapfile -t platforms < <(echo "${raw_manifest}" | jq -r '.manifests[] | "\(.platform.os)/\(.platform.architecture)"' 2>/dev/null)

        if [ ${#platforms[@]} -eq 0 ]; then
            echo "❌ Manifest list has no platforms: ${source_image}" >&2
            return 1
        fi

        echo "   🏗️  Multi-arch manifest list detected: ${#platforms[@]} platforms (${platforms[*]})" >&2

        # Build crane index append arguments
        local index_args=()
        local attempt platform safe_platform per_arch_tag per_arch_image per_arch_digest

        for platform in "${platforms[@]}"; do
            safe_platform="${platform//\//-}"   # linux/amd64 → linux-amd64
            per_arch_tag="mutated-${safe_platform}-${run_id}"
            per_arch_image="${dest_repo}:${per_arch_tag}"

            attempt=1
            while [ ${attempt} -le ${max_retries} ]; do
                if crane mutate "${source_image}" \
                    --platform "${platform}" \
                    --label "io.konflux.test.digest-mutation=${label_value}" \
                    --tag "${per_arch_image}" 2>&1 | grep -v 'Pulling\|Pushed' >&2; then
                    break
                fi
                if [ ${attempt} -lt ${max_retries} ]; then
                    echo "   ⚠️  Platform ${platform} attempt ${attempt}/${max_retries} failed, retrying..." >&2
                    sleep ${retry_delay}
                fi
                attempt=$((attempt + 1))
                if [ ${attempt} -gt ${max_retries} ]; then
                    echo "❌ Failed to mutate platform ${platform} after ${max_retries} attempts: ${source_image}" >&2
                    return 1
                fi
            done

            # Convert to OCI format so crane index append builds an OCI index.
            # Quay repos that hold OCI images reject Docker manifest media types;
            # crane mutate produces Docker-format single-arch manifests by default.
            if ! skopeo copy --format oci \
                    ${DOCKER_CONFIG:+--authfile "${DOCKER_CONFIG}/config.json"} \
                    "docker://${per_arch_image}" \
                    "docker://${per_arch_image}" >/dev/null 2>&1; then
                echo "❌ Failed to convert platform ${platform} image to OCI format: ${per_arch_image}" >&2
                return 1
            fi

            per_arch_digest=$(crane digest "${per_arch_image}" 2>/dev/null || echo "")
            if [ -z "${per_arch_digest}" ]; then
                echo "❌ Could not get digest for mutated platform image: ${per_arch_image}" >&2
                return 1
            fi
            echo "   ✅ Platform ${platform}: ${per_arch_digest}" >&2
            index_args+=("-m" "${dest_repo}@${per_arch_digest}")
        done

        # Re-assemble the manifest list from per-arch digests
        attempt=1
        while [ ${attempt} -le ${max_retries} ]; do
            if crane index append \
                "${index_args[@]}" \
                -t "${dest_image}" >&2 2>&1; then
                break
            fi
            if [ ${attempt} -lt ${max_retries} ]; then
                echo "   ⚠️  Index assembly attempt ${attempt}/${max_retries} failed, retrying..." >&2
                sleep ${retry_delay}
            fi
            attempt=$((attempt + 1))
            if [ ${attempt} -gt ${max_retries} ]; then
                echo "❌ Failed to assemble manifest list after ${max_retries} attempts" >&2
                return 1
            fi
        done

        local new_digest
        new_digest=$(crane digest "${dest_image}" 2>/dev/null || echo "")
        if [ -z "${new_digest}" ]; then
            echo "❌ Could not get digest for assembled manifest list: ${dest_image}" >&2
            return 1
        fi

        echo "${dest_repo}@${new_digest}"
        return 0

    else
        # ── Single-arch path ──────────────────────────────────────────────────
        local attempt=1
        while [ ${attempt} -le ${max_retries} ]; do
            if crane mutate "${source_image}" \
                --label "io.konflux.test.digest-mutation=${label_value}" \
                --tag "${dest_image}" 2>&1 | grep -v 'Pulling\|Pushed' >&2; then

                local new_digest
                new_digest=$(crane digest "${dest_image}" 2>/dev/null || echo "")
                if [ -n "${new_digest}" ]; then
                    echo "${dest_repo}@${new_digest}"
                    return 0
                fi
            fi

            if [ ${attempt} -lt ${max_retries} ]; then
                echo "   ⚠️  Attempt ${attempt}/${max_retries} failed, retrying in ${retry_delay}s..." >&2
                sleep ${retry_delay}
                attempt=$((attempt + 1))
            else
                echo "❌ Failed to mutate image after ${max_retries} attempts: ${source_image}" >&2
                return 1
            fi
        done

        return 1
    fi
}

# Sign a mutated image and re-attach the original image's SLSA provenance
# so that Enterprise Contract (verify-conforma, STRICT=true, @slsa3) accepts it.
#
# WHY we copy the original attestation instead of fabricating one:
#   EC's trusted_task.trusted rule checks that every build step in the SLSA
#   provenance references a pinned, trusted Tekton task bundle from the allowlist.
#   A synthetic provenance (e.g. "crane mutate") has no Tekton bundle reference
#   and would fail that check.  The original image was built by PAC/Tekton Chains
#   and its attestation already has real trusted-task references — we just need to
#   re-sign it for the new (mutated) digest.
#
# Multi-arch handling:
#   cosign sign/attest with --recursive signs the manifest list index AND each
#   individual arch digest automatically. This is what verify-conforma expects
#   when checking multi-arch images — every platform must be individually signed.
#
# Strategy:
#   1. cosign sign   — new signature covering the mutated digest (+ each arch via --recursive)
#   2. cosign download attestation — fetch the original SLSA predicate
#   3. cosign attest — re-attach the original predicate; cosign sets the
#                      subject automatically to the mutated digest
#
# This function is MANDATORY when ENABLE_DIGEST_MUTATION=true.
# Any failure here is fatal — there is no fallback.
#
# Prerequisites (set up in the tool-install block below):
#   COSIGN_KEY_FILE  - path to freshly-generated PEM private key (empty password)
#   COSIGN_PASSWORD  - passphrase for the key (always empty — we generate the key)
#   DOCKER_CONFIG    - docker config dir with pull credentials for source images
#
# Arguments:
#   $1 mutated_image  - full digest ref of the mutated image  (repo@sha256:...)
#   $2 source_image   - full digest ref of the original image (repo@sha256:...)
sign_and_attest_mutated_image() {
    local mutated_image="$1"
    local source_image="$2"

    # ── 1. Sign the mutated image ────────────────────────────────────────────
    echo "   🔑 Signing ${mutated_image##*/} (--recursive covers all arch digests) ..." >&2
    COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
    COSIGN_YES=1 \
    cosign sign \
        --key "${COSIGN_KEY_FILE}" \
        --tlog-upload=false \
        --recursive \
        "${mutated_image}" 2>&1 | grep -v '^$' >&2

    # ── 2. Download the original image's SLSA predicate ─────────────────────
    # cosign download attestation returns newline-delimited JSON objects, each
    # with a base64-encoded .payload field containing the in-toto Statement.
    # We take the first SLSA provenance statement and extract its predicate.
    echo "   📥 Fetching SLSA provenance from original image ..." >&2

    local predicate_file statement_file
    predicate_file="$(mktemp --suffix=-slsa-predicate.json)"
    statement_file="$(mktemp --suffix=-slsa-statement.json)"

    # cosign respects DOCKER_CONFIG for registry auth (pull credentials)
    COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
    cosign download attestation "${source_image}" 2>/dev/null \
        | jq -r 'select(.payload != null) | .payload' \
        | while IFS= read -r payload; do
            statement="$(echo "${payload}" | base64 -d 2>/dev/null)" || continue
            pred_type="$(echo "${statement}" | jq -r '.predicateType // ""' 2>/dev/null)"
            if [[ "${pred_type}" == *"slsa.dev/provenance"* ]]; then
                echo "${statement}" > "${statement_file}"
                echo "${statement}" | jq '.predicate' > "${predicate_file}"
                break
            fi
          done

    if [ ! -s "${predicate_file}" ]; then
        echo "❌ Could not extract SLSA provenance from source image: ${source_image}" >&2
        echo "   The original image must have a cosign SLSA attestation for mutation signing to work" >&2
        rm -f "${predicate_file}" "${statement_file}"
        exit 1
    fi

    # Detect the predicate type from the original attestation so the re-attached
    # attestation uses the correct type (v0.2 → slsaprovenance, v1.0 → slsaprovenance1).
    local pred_type_url cosign_type
    pred_type_url="$(jq -r '.predicateType // ""' "${statement_file}")"
    if [[ "${pred_type_url}" == *"/v1" ]]; then
        cosign_type="slsaprovenance1"
    else
        cosign_type="slsaprovenance"
    fi
    echo "   📋 Predicate type: ${pred_type_url} (cosign type: ${cosign_type})" >&2
    rm -f "${statement_file}"

    # ── 3. Re-attach the original predicate to the mutated image ────────────
    # cosign attest automatically sets the in-toto Statement subject to the
    # mutated image's digest, so EC's subject-match check passes.
    #
    # cosign attest does not support --recursive, so for manifest lists we
    # must attest the index AND each individual arch digest explicitly.
    # EC verifies every arch digest it finds in the snapshot manifest list.

    # Build list of images to attest: always start with the index itself.
    local attest_targets=("${mutated_image}")

    # If mutated_image is a manifest list, collect per-arch digests.
    local mutated_repo="${mutated_image%@*}"
    local raw_index
    raw_index=$(skopeo inspect --raw \
        ${DOCKER_CONFIG:+--authfile "${DOCKER_CONFIG}/config.json"} \
        "docker://${mutated_image}" 2>/dev/null)
    local arch_digests
    mapfile -t arch_digests < <(echo "${raw_index}" | jq -r '.manifests[].digest // empty' 2>/dev/null)
    for arch_digest in "${arch_digests[@]}"; do
        attest_targets+=("${mutated_repo}@${arch_digest}")
    done

    # ── 2.5 Copy original Tekton Chains attestations to mutated locations ────
    # mobster (process-component-sboms) verifies attestations with the hardcoded
    # key k8s://openshift-pipelines/public-key (Tekton Chains). Our own cosign
    # attest (step 3) uses a different test key. Solution: copy the original
    # Tekton Chains .att OCI artifact to the mutated image's .att location first.
    # cosign attest in step 3 then APPENDs our attestation to that OCI index,
    # so sha256-MUTATED.att contains BOTH attestations:
    #   - Tekton Chains attestation → mobster passes (k8s://openshift-pipelines/public-key)
    #   - Our attestation           → verify-conforma passes (our EC test key)
    echo "   📋 Copying Tekton Chains attestations to mutated image locations ..." >&2

    local source_repo="${source_image%@*}"
    local source_digest="${source_image#*@}"          # sha256:ABCD...
    local source_att_tag="${source_digest/:/-}.att"   # sha256-ABCD....att
    local mutated_index_digest="${mutated_image#*@}"  # sha256:WXYZ...
    local mutated_index_att_tag="${mutated_index_digest/:/-}.att"

    # Copy index-level Tekton Chains attestation (non-fatal if absent)
    if crane manifest "${source_repo}:${source_att_tag}" >/dev/null 2>&1; then
        crane copy \
            "${source_repo}:${source_att_tag}" \
            "${mutated_repo}:${mutated_index_att_tag}" >/dev/null 2>&1 \
            && echo "   ✅ Index Tekton Chains attestation copied" >&2 \
            || echo "   ⚠️  Could not copy index Tekton Chains attestation (non-fatal)" >&2
    else
        echo "   ⚠️  No Tekton Chains attestation at source index (non-fatal)" >&2
    fi

    # Copy per-arch Tekton Chains attestations by matching platform to original arch digest
    local source_raw_index
    source_raw_index=$(skopeo inspect --raw \
        ${DOCKER_CONFIG:+--authfile "${DOCKER_CONFIG}/config.json"} \
        "docker://${source_image}" 2>/dev/null)

    for arch_digest in "${arch_digests[@]}"; do
        local platform os arch orig_arch_digest orig_arch_att_tag mutated_arch_att_tag
        platform=$(echo "${raw_index}" \
            | jq -r --arg d "${arch_digest}" \
                '.manifests[] | select(.digest==$d) | "\(.platform.os)/\(.platform.architecture)"' \
                2>/dev/null)
        [ -z "${platform}" ] && continue

        os="${platform%%/*}"
        arch="${platform##*/}"
        orig_arch_digest=$(echo "${source_raw_index}" \
            | jq -r --arg os "${os}" --arg arch "${arch}" \
                '.manifests[] | select(.platform.os==$os and .platform.architecture==$arch) | .digest' \
                2>/dev/null)
        [ -z "${orig_arch_digest}" ] && continue

        orig_arch_att_tag="${orig_arch_digest/:/-}.att"
        mutated_arch_att_tag="${arch_digest/:/-}.att"

        if crane manifest "${source_repo}:${orig_arch_att_tag}" >/dev/null 2>&1; then
            crane copy \
                "${source_repo}:${orig_arch_att_tag}" \
                "${mutated_repo}:${mutated_arch_att_tag}" >/dev/null 2>&1 \
                || echo "   ⚠️  Could not copy ${platform} Tekton Chains attestation (non-fatal)" >&2
        fi
    done
    echo "   ✅ Tekton Chains attestations ready (index + ${#arch_digests[@]} arch digest(s))" >&2

    echo "   📋 Attesting ${#attest_targets[@]} image(s) with original SLSA provenance ..." >&2
    local target
    for target in "${attest_targets[@]}"; do
        COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
        COSIGN_YES=1 \
        cosign attest \
            --key "${COSIGN_KEY_FILE}" \
            --predicate "${predicate_file}" \
            --type "${cosign_type}" \
            --tlog-upload=false \
            "${target}" 2>&1 | grep -v '^$' >&2
    done

    rm -f "${predicate_file}"
    echo "   ✅ Signed + attested (original provenance, ${#attest_targets[@]} digest(s))" >&2

    # ── 4. Attach stub SBOMs to each per-arch manifest ───────────────────────
    # push-rpm-data-to-pyxis runs `cosign download sbom --platform <arch> <index>`
    # for every pyxisImages entry. Mutated images have no build-time SBOMs, so
    # all 800 cosign calls fail → retry storms → OOM-kill after ~766 iterations.
    # Fix: attach a minimal SPDX stub to each arch digest so the download
    # succeeds and the step can complete normally.
    local stub_sbom
    stub_sbom="$(mktemp --suffix=-stub.spdx.json)"
    cat > "${stub_sbom}" <<'STUB_SBOM_EOF'
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "stub-sbom",
  "documentNamespace": "https://stub-sbom/placeholder",
  "packages": [],
  "relationships": []
}
STUB_SBOM_EOF

    echo "   📎 Attaching stub SBOMs to ${#arch_digests[@]} arch manifest(s) ..." >&2
    local _attached=0
    for arch_digest in "${arch_digests[@]}"; do
        COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" \
        cosign attach sbom \
            --sbom "${stub_sbom}" \
            --type spdx \
            "${mutated_repo}@${arch_digest}" 2>&1 | grep -v '^$' >&2 \
        && _attached=$((_attached + 1)) \
        || echo "   ⚠️  Failed to attach stub SBOM to ${arch_digest} (non-fatal)" >&2
    done
    echo "   ✅ Stub SBOMs attached (${_attached}/${#arch_digests[@]} arch digests)" >&2
    rm -f "${stub_sbom}"

}

# Convert one entry from the pool into a concrete container image reference.
# Supported formats:
# - component name: v4-15-apiserver-watcher-01
# - repo path: quay.io/.../component  (tagless)
# - full image ref: quay.io/.../component:tag or quay.io/.../component@sha256:...
resolve_container_image() {
    local entry="$1"

    # If entry is a bare component name, build the target image ref in the test namespace.
    if [[ "${entry}" != *"/"* ]]; then
        echo "quay.io/redhat-user-workloads-stage/${NAMESPACE}/${entry}:stable"
        return 0
    fi

    # If entry already has digest or tag, use as-is
    if [[ "${entry}" == *"@"* ]] || [[ "${entry}" == *":"* ]]; then
        echo "${entry}"
        return 0
    fi

    # Otherwise treat it as a repo path and default to :latest
    echo "${entry}:latest"
    return 0
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

    # Try skopeo first (fastest and most reliable)
    # Note: Static image pool images are publicly readable, no auth needed for inspection
    if command -v skopeo &>/dev/null; then
        local digest
        local repo="${image_ref%:*}"  # Strip :tag

        if digest=$(skopeo inspect --format '{{.Digest}}' "docker://${image_ref}" 2>/dev/null); then
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
        if manifest_digest=$(curl -s "${api_url}" 2>/dev/null | jq -r '.manifest_digest // empty' 2>/dev/null); then
            if [ -n "${manifest_digest}" ]; then
                echo "quay.io/${repo}@${manifest_digest}"
                return 0
            fi
        fi
    fi

    echo "❌ Error: Could not resolve tag to digest: ${image_ref}" >&2
    return 1
}

# ============================================================================
# Tool installation and credential setup (when mutation is enabled)
# ============================================================================

if [ "${ENABLE_DIGEST_MUTATION}" = "true" ]; then

    # ── crane ────────────────────────────────────────────────────────────────
    if ! command -v crane &>/dev/null; then
        echo "🔧 crane not found - installing..." >&2

        CRANE_BIN_DIR=$(mktemp -d)
        export PATH="${CRANE_BIN_DIR}:${PATH}"

        CRANE_VERSION="v0.19.1"
        CRANE_URL="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz"

        if ! curl -sL "${CRANE_URL}" | tar -xz -C "${CRANE_BIN_DIR}" crane 2>/dev/null; then
            echo "❌ Failed to install crane from ${CRANE_URL}" >&2
            exit 1
        fi

        if ! command -v crane &>/dev/null; then
            echo "❌ crane installation failed - not found in PATH" >&2
            exit 1
        fi

        echo "   ✅ crane installed successfully" >&2
    fi

    # ── cosign ───────────────────────────────────────────────────────────────
    if ! command -v cosign &>/dev/null; then
        echo "🔧 cosign not found - installing..." >&2

        COSIGN_BIN_DIR="${CRANE_BIN_DIR:-$(mktemp -d)}"
        export PATH="${COSIGN_BIN_DIR}:${PATH}"

        COSIGN_VERSION="v2.4.1"
        COSIGN_URL="https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"

        if ! curl -sL "${COSIGN_URL}" -o "${COSIGN_BIN_DIR}/cosign"; then
            echo "❌ Failed to install cosign from ${COSIGN_URL}" >&2
            exit 1
        fi

        chmod +x "${COSIGN_BIN_DIR}/cosign"

        if ! command -v cosign &>/dev/null; then
            echo "❌ cosign installation failed - not found in PATH" >&2
            exit 1
        fi

        echo "   ✅ cosign installed successfully" >&2
    fi

    # ── Self-generated cosign key pair ───────────────────────────────────────
    # We generate a fresh ECDSA key pair per run.  The public half is stored in
    # the managed namespace under EC_PUBKEY_SECRET_NAME so that the EC policy
    # (publicKey: k8s://${managed_namespace}/${EC_PUBKEY_SECRET_NAME}) can verify it.
    # The name is per-run (set by test.sh) to avoid collisions when concurrent test
    # runs overlap: a previous run's cleanup must not delete the current run's key.
    EC_PUBKEY_SECRET_NAME="${EC_PUBKEY_SECRET_NAME:-test-ec-pubkey}"

    echo "🔑 Generating test cosign key pair for mutation signing ..." >&2

    COSIGN_KEY_DIR="$(mktemp -d)"

    # cosign generate-key-pair writes cosign.key + cosign.pub to CWD.
    # COSIGN_PASSWORD="" and COSIGN_YES=1 make it fully non-interactive.
    if ! ( cd "${COSIGN_KEY_DIR}" && COSIGN_PASSWORD="" COSIGN_YES=1 cosign generate-key-pair >&2 2>&1 ); then
        echo "❌ cosign generate-key-pair failed" >&2
        exit 1
    fi

    COSIGN_KEY_FILE="${COSIGN_KEY_DIR}/cosign.key"
    COSIGN_PASSWORD=""

    if [ ! -s "${COSIGN_KEY_FILE}" ]; then
        echo "❌ Generated cosign.key is empty — aborting" >&2
        exit 1
    fi

    export COSIGN_KEY_FILE COSIGN_PASSWORD

    # Publish the public key as a K8s secret so EC can read it.
    # Using --dry-run=client | apply makes this idempotent (safe on re-runs).
    echo "   📤 Storing public key in ${MANAGED_NAMESPACE}/${EC_PUBKEY_SECRET_NAME} ..." >&2
    if ! kubectl create secret generic "${EC_PUBKEY_SECRET_NAME}" \
            -n "${MANAGED_NAMESPACE}" \
            --from-file=cosign.pub="${COSIGN_KEY_DIR}/cosign.pub" \
            --dry-run=client -o yaml 2>&1 | kubectl apply -f - >&2 2>&1; then
        echo "❌ Failed to store EC public key secret in ${MANAGED_NAMESPACE}" >&2
        exit 1
    fi

    echo "   ✅ Signing key ready (public key in ${MANAGED_NAMESPACE}/${EC_PUBKEY_SECRET_NAME})" >&2

    # ── Quay push credentials from imagerepository secrets ───────────────────
    # Each Konflux component gets a dedicated ImageRepository resource whose
    # push secret (imagerepository-for-large-snapshot-build-*-image-push) has
    # write access to quay.io/redhat-user-workloads-stage/<namespace>/<component>.
    # We merge all of them into a single DOCKER_CONFIG so crane/skopeo/cosign
    # can push mutated images directly to redhat-user-workloads-stage — no remap.
    echo "🔐 Building merged Quay credentials from imagerepository push secrets ..." >&2

    mapfile -t IMGREPOSITORY_SECRETS < <(
        kubectl get secrets -n "${NAMESPACE}" -o name 2>/dev/null \
            | grep "imagerepository-for-large-snapshot-build.*-image-push" \
            | sed 's|secret/||'
    )

    if [ ${#IMGREPOSITORY_SECRETS[@]} -eq 0 ]; then
        echo "❌ No imagerepository push secrets found in ${NAMESPACE}" >&2
        echo "   Expected secrets matching: imagerepository-for-large-snapshot-build*-image-push" >&2
        echo "   These are created by Konflux ImageRepository CRs for each component." >&2
        exit 1
    fi

    echo "   Found ${#IMGREPOSITORY_SECRETS[@]} imagerepository push secrets" >&2

    # Merge all per-component dockerconfigjson entries into one config.
    MERGED_AUTHS="{}"
    for secret_name in "${IMGREPOSITORY_SECRETS[@]}"; do
        secret_auths=$(kubectl get secret "${secret_name}" -n "${NAMESPACE}" \
            -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null \
            | base64 -d | jq -c '.auths // {}' 2>/dev/null)
        if [ -n "${secret_auths}" ] && [ "${secret_auths}" != "null" ] && [ "${secret_auths}" != "{}" ]; then
            MERGED_AUTHS=$(jq -cn --argjson base "${MERGED_AUTHS}" --argjson new "${secret_auths}" '$base + $new')
        fi
    done

    # Also include the general pull credential so cosign can read source images
    # and push signature/attestation artifacts to quay.io in general.
    PULL_SECRET_AUTHS=$(kubectl get secret test-quay-token-secret -n "${NAMESPACE}" \
        -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null \
        | base64 -d | jq -c '.auths // {}' 2>/dev/null)
    if [ -n "${PULL_SECRET_AUTHS}" ] && [ "${PULL_SECRET_AUTHS}" != "null" ]; then
        MERGED_AUTHS=$(jq -cn --argjson base "${MERGED_AUTHS}" --argjson new "${PULL_SECRET_AUTHS}" '$base + $new')
    fi

    MUTATION_DOCKER_CONFIG=$(mktemp -d)
    export DOCKER_CONFIG="${MUTATION_DOCKER_CONFIG}"
    printf '{"auths":%s}\n' "${MERGED_AUTHS}" > "${DOCKER_CONFIG}/config.json"

    echo "   ✅ Push credentials merged (${#IMGREPOSITORY_SECRETS[@]} components → quay.io/redhat-user-workloads-stage)" >&2

    echo "🔄 Digest mutation enabled (Run ID: ${DIGEST_MUTATION_RUN_ID})" >&2
    echo "   This will create NEW digests for all images (worst-case signing)" >&2
    echo "" >&2
fi

echo "🔍 Resolving and processing image references..." >&2

declare -a RESOLVED_IMAGES=()

for (( i=0; i<COMPONENT_COUNT && i<${#IMAGE_POOL[@]}; i++ )); do
    image_entry="${IMAGE_POOL[$i]}"

    # Resolve to full image ref (handles bare component names)
    image_ref="$(resolve_container_image "${image_entry}")"

    # Resolve tag to digest — hard exit on failure
    resolved_image="$(resolve_tag_to_digest "${image_ref}")"

    # If mutation enabled, mutate → sign → attest (all steps mandatory)
    if [ "${ENABLE_DIGEST_MUTATION}" = "true" ]; then
        pre_mutation_image="${resolved_image}"

        mutated_image="$(mutate_image_digest "${resolved_image}" "${DIGEST_MUTATION_RUN_ID}")"
        resolved_image="${mutated_image}"
        echo "   [${i}] ✅ ${image_entry} → mutated" >&2

        sign_and_attest_mutated_image \
            "${mutated_image}" \
            "${pre_mutation_image}"
    fi

    RESOLVED_IMAGES+=("${resolved_image}")

    # Show progress every 20 images (mutation already logs per-image)
    if [ "${ENABLE_DIGEST_MUTATION}" != "true" ] && [ $((i % 20)) -eq 0 ] && [ $i -gt 0 ]; then
        echo "   Resolved ${i}/${#IMAGE_POOL[@]} images..." >&2
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
    test.appstudio.openshift.io/available-images: "${ACTUAL_COMPONENT_COUNT}"
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
