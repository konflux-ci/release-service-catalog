#!/usr/bin/env bash
#
# test.sh - Multi-arch / manifest list idempotency
#
# Same flow as base idempotent test; component uses docker-build-multi-platform-oci-ta
# so the snapshot has a manifest list digest. Filter queries Pyxis by that digest.
#

# shellcheck source=../rh-push-to-registry-redhat-io-idempotent/test.sh
source "${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent/test.sh"

# Override decrypt_secrets: always pull the GitHub token fresh from the base suite's
# vault so we never rely on a stale token baked into resources/tenant/secrets/.
# Managed secrets are already baked into resources/managed/secrets/ and stay as-is.
decrypt_secrets() {
    local base_suite_dir="${SUITE_DIR}/../rh-push-to-registry-redhat-io-idempotent"
    (
        . "${LIB_DIR}/test-functions.sh"
        decrypt_secrets "${base_suite_dir}"
    )
    # Copy the freshly-decrypted tenant secret (valid GitHub token) into this suite.
    local base_tenant_secrets="${base_suite_dir}/resources/tenant/secrets/tenant-secrets.yaml"
    local tenant_secrets_file="${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml"
    mkdir -p "${SUITE_DIR}/resources/tenant/secrets"
    cp "${base_tenant_secrets}" "${tenant_secrets_file}"
}

# Override resolve_pyxis_poll_digest: for a manifest list digest, resolve to
# the first per-arch digest so the polling job queries Pyxis correctly.
# Pyxis stores per-arch records (not manifest list records), so polling by the
# manifest list digest always returns 0 results.
resolve_pyxis_poll_digest() {
    local image_digest="$1"
    local snapshot_name="$2"

    if [ -z "${image_digest}" ] || [ "${image_digest}" = "null" ] \
        || [ -z "${snapshot_name}" ] || [ "${snapshot_name}" = "null" ]; then
        echo "${image_digest}"
        return 0
    fi

    local container_image
    container_image=$(kubectl get snapshot -n "${tenant_namespace}" "${snapshot_name}" \
        -o jsonpath='{.spec.components[0].containerImage}' 2>/dev/null || echo "")

    if [ -z "${container_image}" ] || [[ "${container_image}" != *@sha256:* ]]; then
        echo "${image_digest}"
        return 0
    fi

    local ml_registry="${container_image%%/*}"
    local ml_repo="${container_image#*/}"; ml_repo="${ml_repo%@*}"
    local ml_token
    ml_token=$(curl -sf --max-time 10 \
        "https://${ml_registry}/v2/auth?service=${ml_registry}&scope=repository:${ml_repo}:pull" \
        | jq -r '.token // ""' 2>/dev/null || echo "")
    local ml_accept="application/vnd.docker.distribution.manifest.list.v2+json"
    ml_accept="${ml_accept},application/vnd.oci.image.index.v1+json"
    local ml_manifest
    ml_manifest=$(curl -sf --max-time 15 \
        -H "Authorization: Bearer ${ml_token}" \
        -H "Accept: ${ml_accept}" \
        "https://${ml_registry}/v2/${ml_repo}/manifests/${image_digest}" \
        2>/dev/null || echo "{}")
    local first_arch_digest
    first_arch_digest=$(echo "${ml_manifest}" \
        | jq -r '.manifests[0]?.digest // ""' 2>/dev/null || echo "")

    if [ -n "${first_arch_digest}" ]; then
        echo "Manifest list detected — polling by first arch digest: ${first_arch_digest}" >&2
        echo "${first_arch_digest}"
    else
        echo "${image_digest}"
    fi
}

# Override patch_component_source_before_merge:
# configure-pac generates .tekton/<component>-push.yaml (with correct hardcoded branch
# name) and .tekton/<component>-pull-request.yaml. The push file uses
# docker-build-multi-platform-oci-ta:devel (from the pipeline annotation on the
# component) but does NOT include build-platforms or build-image-index, so the build
# defaults to linux/x86_64 only.
# This function:
#  1. Patches .tekton/<component>-push.yaml to add build-platforms + build-image-index
#  2. Deletes .tekton/<component>-pull-request.yaml (not needed for the test)
#  3. Deletes .tekton/push.yaml from e2e-base-multi-arch (its {{target_branch}} CEL
#     expression is never substituted by PaC, so it would never trigger a build)
patch_component_source_before_merge() {
    echo "Patching PR: injecting multi-arch params into configure-pac push pipeline..."

    local pr_branch
    pr_branch=$(gh api "repos/${component_repo_name}/pulls/${pr_number}" \
        --jq '.head.ref' 2>/dev/null || echo "")
    if [ -z "${pr_branch}" ]; then
        echo "⚠️  Could not determine PR branch — skipping patch"
        return 0
    fi
    echo "PR branch: ${pr_branch}"

    # --- 1. Patch <component>-push.yaml: add build-platforms + build-image-index ---
    local push_file=".tekton/${component_name}-push.yaml"
    local push_sha push_content
    push_sha=$(gh api \
        "repos/${component_repo_name}/contents/${push_file}?ref=${pr_branch}" \
        --jq '.sha' 2>/dev/null || echo "")
    push_content=$(gh api \
        "repos/${component_repo_name}/contents/${push_file}?ref=${pr_branch}" \
        --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -n "${push_content}" ]; then
        # Replace build-platforms value with multi-arch list and ensure build-image-index is set
        local patched_content
        patched_content=$(printf '%s' "${push_content}" | python3 -c '
import sys, re

content = sys.stdin.read()

# Replace configure-pac single-arch value with multi-arch list
content = re.sub(
    r"(  - name: build-platforms\n    value:\n)    - linux/[^\n]+\n",
    r"\1    - linux/amd64\n    - linux/arm64\n",
    content
)

# Add build-image-index to spec.params if not already there (check before pipelineSpec:)
spec_section = content.split("  pipelineSpec:")[0] if "  pipelineSpec:" in content else content
if "build-image-index" not in spec_section:
    content = re.sub(
        r"(    - linux/arm64\n)",
        r"\1  - name: build-image-index\n    value: true\n",
        content, count=1
    )

sys.stdout.write(content)
')
        local encoded
        encoded=$(printf '%s' "${patched_content}" | base64 -w 0)
        gh api -X PUT \
            "repos/${component_repo_name}/contents/${push_file}" \
            -F message="chore: add multi-arch build-platforms to push pipeline" \
            -F content="${encoded}" \
            -F sha="${push_sha}" \
            -F branch="${pr_branch}" > /dev/null \
            && echo "✅ Patched ${push_file} with multi-arch build-platforms" \
            || echo "⚠️  Failed to patch ${push_file}"
    else
        echo "⚠️  ${push_file} not found in PR branch — cannot patch"
    fi

    # --- 2. Delete <component>-pull-request.yaml (unwanted, creates noisy cancelled PLRs) ---
    local pr_file=".tekton/${component_name}-pull-request.yaml"
    local pr_file_sha
    pr_file_sha=$(gh api \
        "repos/${component_repo_name}/contents/${pr_file}?ref=${pr_branch}" \
        --jq '.sha' 2>/dev/null || echo "")
    if [ -n "${pr_file_sha}" ]; then
        gh api -X DELETE \
            "repos/${component_repo_name}/contents/${pr_file}" \
            -F message="chore: remove pull-request pipeline (not needed for test)" \
            -F sha="${pr_file_sha}" \
            -F branch="${pr_branch}" > /dev/null 2>&1 \
            && echo "✅ Deleted ${pr_file}" \
            || echo "⚠️  Could not delete ${pr_file}"
    fi

    # --- 3. Delete push.yaml from e2e-base-multi-arch (broken {{target_branch}} CEL) ---
    local base_push_sha
    base_push_sha=$(gh api \
        "repos/${component_repo_name}/contents/.tekton/push.yaml?ref=${pr_branch}" \
        --jq '.sha' 2>/dev/null || echo "")
    if [ -n "${base_push_sha}" ]; then
        gh api -X DELETE \
            "repos/${component_repo_name}/contents/.tekton/push.yaml" \
            -F message="chore: remove template push.yaml (CEL {{target_branch}} not substituted by PaC)" \
            -F sha="${base_push_sha}" \
            -F branch="${pr_branch}" > /dev/null 2>&1 \
            && echo "✅ Deleted .tekton/push.yaml (broken template)" \
            || echo "⚠️  Could not delete .tekton/push.yaml"
    fi
}
