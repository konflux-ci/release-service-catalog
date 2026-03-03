#!/bin/bash
set -euo pipefail

# ============================================================================
# build-images.sh - Ensure Konflux components exist with images
# ============================================================================
#
# PURPOSE:
#   Ensure N components exist with built images for large snapshot testing.
#   Simple idempotent strategy: create missing components, build missing images.
#
# STRATEGY (Simplified):
#   1. Loop through components 1-N (default: 200)
#   2. For each component:
#      - If component doesn't exist → CREATE it
#      - If component exists → check if it has an image
#   3. Track counters: existing, created, reused (has image), needs_build
#   4. Stop when N components exist
#   5. Build only components missing images (PAC auto-triggers on creation)
#   6. Wait for builds to complete
#   7. Patch component specs with Quay digests
#   8. Output image pool file
#
# INCREMENTAL BUILD FORMULA:
#   - If existing ≤ 100:        create 100 (capped at target)
#   - If 100 < existing < 200:  create until target
#   - If existing == target:    do nothing
#
# USAGE:
#   ./build-images.sh [component_count] [namespace] [output_file] [force_rebuild]
#
#   IMPORTANT: Build time depends on target count (30s delays between each component creation).
#              Subsequent runs complete in 30-60 seconds by reusing existing builds!
#              Use force_rebuild=true to disable image reuse and create fresh builds.
#
# ARGUMENTS:
#   component_count : Target total components (default: 200)
#   namespace       : Kubernetes namespace for builds (default: dev-release-team-tenant)
#   output_file     : Output file for image pool (default: /tmp/images-pool-TIMESTAMP.txt)
#   force_rebuild   : Delete ALL existing components and rebuild from scratch (default: false)
#                     - true:  Delete all components, create 200 fresh builds
#                     - false: Preserve valid components, add missing to reach 200
#
# ENVIRONMENT:
#   GITHUB_TOKEN        : Required! GitHub PAT with 'repo' permissions for creating branches
#   DISABLE_QUAY_REUSE  : Control Quay image search for invalid/zombie components (default: true)
#                         - true:  Don't search Quay, rebuild invalid components
#                         - false: Search Quay for images, patch if found, rebuild if not
#   PARALLEL_BUILDS     : Max parallel builds (default: 50)
#   BUILD_TIMEOUT       : Total timeout in seconds (default: 64800 = 18 hours for 200 components)
#   CHECK_INTERVAL      : Status check interval in seconds (default: 30)
#   BASE_REPO           : GitHub repository for template source (default: hacbs-release-tests/e2e-base)
#   PAC_TEMPLATE_BRANCH : Branch with PAC config to copy to each component repo (default: konflux-v4-15-apiserver-watcher-01)
#   BASE_BRANCH         : Fallback branch (deprecated, use PAC_TEMPLATE_BRANCH)
#
# OUTPUT:
#   Creates a file with one container image reference per line:
#     quay.io/redhat-user-workloads-stage/namespace/v4-15-apiserver-watcher-01@sha256:abc123...
#     quay.io/redhat-user-workloads-stage/namespace/v4-16-image-service-02@sha256:def456...
#
# PERFORMANCE:
#   Building N new components from scratch:
#     - Prerequisite validation: ~10 seconds (batch queries)
#     - GitHub branch creation: ~N × 30s (30s delay between branches)
#     - Component creation: ~N × 30-90s (30s base + service account wait + 60s batch pause/30)
#     - Wait for ALL components ready: ~1-2 minutes (PAC needs all components before starting)
#     - Build execution: ~20-30 minutes (50 concurrent PAC builds, starts after all components ready)
#     - Auto-retry (if ≤10 failures): ~5-10 minutes (only for transient errors)
#     - Digest extraction: ~1-2 minutes (optimized batch queries)
#   
#   Batch processing (prevents PAC overload):
#     - Creates components in pairs (2 components = 1 pair)
#     - Each component triggers 2 builds: on-pull (PAC PR) + on-push (PR merge)
#     - Waits for builds to start running (up to 2 min)
#     - Then waits 10 minutes before issuing next pair
#     - Prevents overwhelming PAC controller and build infrastructure
#   
#   Examples (with pairs of 2 components + 10min delays, multi-arch builds ~10min each):
#     - 50 components: ~260 minutes (25 pairs × 10min = 250min pauses + ~10min final builds)
#     - 100 components: ~510 minutes (50 pairs × 10min = 500min pauses + ~10min final builds)
#     - 200 components: ~1010 minutes (100 pairs × 10min = 1000min pauses + ~10min final builds)
#   
#   Reuse runs (existing components and branches):
#     - Prerequisite validation: ~5-10 seconds
#     - Component scanning: ~10-20 seconds (finds all existing)
#     - Digest extraction: ~1-2 minutes (from cached data)
#     - Total: ~30-60 seconds (no builds or branch creation needed!)
#   
#   Notes:
#     - Smart reuse: existing branches and components skip creation
#     - Batch queries minimize API load (2-4 calls instead of 1000+)
#     - Progress updates every 30 seconds during build monitoring
#     - 30s delays between creations prevent API rate limits
#     - 6min pause after every 2 components (1 pair) prevents PAC overload
#     - Waits for service accounts to be created (avoids race conditions)
#     - GitHub branches contain EC-compliant PAC pipelines
#
# CLEANUP:
#   Application and components are intentionally LEFT in namespace for debugging.
#   GitHub branches are also LEFT in the repository for reuse.
#   To clean up manually:
#     kubectl delete application <app-name> -n <namespace>
#     # GitHub branches can remain (harmless) or delete via: gh api -X DELETE repos/:owner/:repo/git/refs/heads/:branch
#
# EXAMPLES:
#   # Target 200 total: create up to 50 new components per run - ~20-30 min per run
#   ./build-images.sh 200
#
#   # Subsequent runs reuse existing branches and components - ~30-60 seconds
#   ./build-images.sh 200
#
#   # Force fresh builds (disable image reuse from Quay) - all components rebuilt
#   ./build-images.sh 200 dev-release-team-tenant /tmp/output.txt true
#
#   # Target only 100 total components (useful for smaller tests)
#   ./build-images.sh 100
#
#   # Custom namespace
#   ./build-images.sh 200 my-tenant-namespace
#
#   # Custom parallel builds and faster checks
#   PARALLEL_BUILDS=100 CHECK_INTERVAL=15 ./build-images.sh
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Configuration
# ============================================================================

# Command-line arguments
COMPONENT_COUNT="${1:-204}"  # Target total components (default: 204)
NAMESPACE="${2:-dev-release-team-tenant}"
OUTPUT_FILE="${3:-/tmp/images-pool-$(date +%s).txt}"
FORCE_REBUILD="${4:-false}"  # Delete ALL existing components and rebuild from scratch (default: false)

# DISABLE_QUAY_REUSE: Controls whether to search Quay for images of invalid/zombie components
# - true:  Don't search Quay, just rebuild invalid components (faster, default)
# - false: Search Quay first, if image exists patch component, else rebuild
# This is INDEPENDENT of FORCE_REBUILD (which controls deleting ALL components)
export DISABLE_QUAY_REUSE="${DISABLE_QUAY_REUSE:-true}"

# Multi-version simulation settings - realistic production scenario
# Multiple product versions each with multiple components
# Default 7: floor(200/7)=28 per version, last version gets remainder (200-28*6=32).
PRODUCT_VERSIONS="${PRODUCT_VERSIONS:-7}"              # Number of product versions to use

# Application naming - one app per product version
# Instead of one large app, create multiple apps representing different versions
# Use stable naming (no timestamp) to enable image reuse across test runs
APP_PREFIX="large-snapshot-build"
# Prefix for generated component names; override via COMPONENT_NAME_PREFIX env var
# Default: "multi" → multi-v4-15-apiserver-watcher-01
COMPONENT_NAME_PREFIX="${COMPONENT_NAME_PREFIX:-multi}"

# Architecture build mode: "multi" (default) or "single"
# multi → docker-build-multi-platform-oci-ta, 4 arches (amd64/arm64/s390x/ppc64le)
# single → docker-build-oci-ta, amd64 only (faster builds, ~4× less signing load)
BUILD_ARCH_MODE="${BUILD_ARCH_MODE:-multi}"

# Pre-compute arch-specific values used in component YAML heredocs below
if [ "${BUILD_ARCH_MODE}" = "multi" ]; then
    _BUILD_PIPELINE_NAME="docker-build-multi-platform-oci-ta"
    _BUILD_PIPELINE_BUNDLE="quay.io/konflux-ci/tekton-catalog/pipeline-docker-build-multi-platform-oci-ta:devel"
    # Injected verbatim into heredocs; empty string = no extra annotation lines
    _ARCH_ANNOTATIONS='    build.appstudio.openshift.io/multi-platform-required: "true"
    build.appstudio.openshift.io/request-platforms: "linux/amd64,linux/arm64,linux/s390x,linux/ppc64le"'
else
    _BUILD_PIPELINE_NAME="docker-build-oci-ta"
    _BUILD_PIPELINE_BUNDLE="quay.io/konflux-ci/tekton-catalog/pipeline-docker-build-oci-ta:devel"
    _ARCH_ANNOTATIONS=""
fi

# Base repository (template source - has PAC config and Dockerfile)
# Using dedicated template repo with 'template' in name to avoid component collision
# main branch contains .tekton/template-push.yaml + Dockerfile for push-only multi-arch builds
BASE_REPO="${BASE_REPO:-hacbs-release-tests/rh-adv-large-snapshot-template}"
PAC_TEMPLATE_BRANCH="${PAC_TEMPLATE_BRANCH:-main}"
BASE_BRANCH="${BASE_BRANCH:-push-to-external-registry-base}"
BASE_GITHUB_URL="https://github.com/${BASE_REPO}"

# One repo per component (OCP-style, like existing Konflux tests)
# Each component gets its own repo: hacbs-release-tests/rh-adv-large-{component_name}
COMPONENT_REPO_ORG="${COMPONENT_REPO_ORG:-hacbs-release-tests}"
COMPONENT_REPO_PREFIX="${COMPONENT_REPO_PREFIX:-rh-adv}"
COMPONENT_BRANCH_PREFIX="${COMPONENT_BRANCH_PREFIX:-component}"  # Each component uses its own branch: component-{name}

# Build orchestration settings
PARALLEL_BUILDS="${PARALLEL_BUILDS:-50}"      # Max concurrent builds
BUILD_TIMEOUT="${BUILD_TIMEOUT:-64800}"       # 18 hours total (for 200 components with 10-min batching and multi-arch builds)
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"        # Status check every 30s

# Retry settings
MAX_RETRIES=3
RETRY_DELAY=5
# Note: Small delays between creations (3s) help avoid rate limits + retry logic handles errors

# Product version patterns - realistic version numbering
# Simulates building multiple product releases with realistic version numbers
VERSION_PATTERNS=(
    "4.15"
    "4.16"
    "4.17"
    "4.18"
    "4.19"
    "4.20"
    "4.21"
    "4.22"
    "4.23"
    "4.24"
)

# Quay.io API authentication (optional - enables private repo access)
QUAY_TOKEN=""
QUAY_SECRET_NAME="${QUAY_SECRET_NAME:-test-quay-token-secret}"
if kubectl get secret "${QUAY_SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    QUAY_AUTH=$(kubectl get secret "${QUAY_SECRET_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d | \
        jq -r '.auths["quay.io"].auth // empty' 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -n "${QUAY_AUTH}" ]; then
        QUAY_TOKEN="${QUAY_AUTH#*:}"
        echo "ℹ️  ✓ Quay.io API authentication enabled (using ${QUAY_SECRET_NAME})" >&2
    fi
fi

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo "ℹ️  $*" >&2
}

log_success() {
    echo "✅ $*" >&2
}

log_warning() {
    echo "⚠️  $*" >&2
}

log_error() {
    echo "❌ $*" >&2
}

log_section() {
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "$*" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
}

# Check if a component already has a successful build with extractable image digest
# Returns 0 if component exists with successful build, 1 otherwise
component_has_successful_build() {
    local component_name="$1"
    local namespace="$2"
    
    # Check if component exists
    if ! kubectl get component "${component_name}" -n "${namespace}" &>/dev/null; then
        return 1
    fi
    
    # Try to get image digest from component status (preferred)
    # CRITICAL: Konflux uses .status.lastPromotedImage (NOT .status.containerImage or spec.containerImage)
    local promoted_image
    promoted_image=$(kubectl get component "${component_name}" -n "${namespace}" \
        -o jsonpath='{.status.lastPromotedImage}' 2>/dev/null || echo "")
    
    # If status has valid digest, component is ready to reuse
    if [ -n "${promoted_image}" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
        return 0
    fi
    
    # Fallback: Check if there's a successful PipelineRun
    local plr_name
    plr_name=$(kubectl get pipelinerun -n "${namespace}" \
        -l "appstudio.openshift.io/component=${component_name}" \
        -l "pipelines.appstudio.openshift.io/type=build" \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
    
    if [ -n "${plr_name}" ]; then
        local plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${namespace}" \
            -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)
        
        if [ "$plr_status" = "True" ]; then
            return 0
        fi
    fi
    
    # No usable build found
    return 1
}

# Check if image exists on Quay.io and return the digest
# Returns:
#   0 - Image found (QUAY_IMAGE_DIGEST set)
#   1 - No image (repo exists but no valid tags)
#   2 - Cannot determine (403/404/network error - might be private repo or wrong registry)
check_quay_image_exists() {
    local component_name="$1"
    local namespace="$2"
    local repo_url="https://quay.io/api/v1/repository/redhat-user-workloads-stage/${namespace}/${component_name}"
    
    # Build curl command with optional authentication
    local curl_auth_args=()
    if [ -n "${QUAY_TOKEN}" ]; then
        curl_auth_args=(-H "Authorization: Bearer ${QUAY_TOKEN}")
    fi
    
    # Query Quay.io API (with authentication if available)
    local response
    response=$(curl -s -w "\n%{http_code}" "${curl_auth_args[@]}" "${repo_url}" 2>/dev/null || echo "000")
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)
    
    # Debug: Show what we got
    if [ "${QUAY_CHECK_DEBUG:-false}" = "true" ]; then
        log_info "      [DEBUG] Quay check: ${component_name}"
        log_info "      [DEBUG] URL: ${repo_url}"
        log_info "      [DEBUG] HTTP: ${http_code}"
        log_info "      [DEBUG] Auth: ${QUAY_TOKEN:+enabled}"
    fi
    
    # Check for access errors (might be private repo without auth, or wrong registry)
    if [ "$http_code" = "403" ] || [ "$http_code" = "404" ] || [ "$http_code" = "000" ]; then
        if [ "${QUAY_CHECK_DEBUG:-false}" = "true" ]; then
            log_info "      [DEBUG] Access error or not found - cannot determine if image exists"
        fi
        return 2  # Cannot determine (access denied, not found, or network error)
    fi
    
    if [ "$http_code" = "200" ]; then
        # Repository exists - get tags, excluding attestation artifacts
        local tags_url="${repo_url}/tag/?onlyActiveTags=true&limit=10"
        local tags_response
        tags_response=$(curl -s "${curl_auth_args[@]}" "${tags_url}" 2>/dev/null)
        
        # Find first tag that's NOT .sig, .att, .sbom, .dockerfile (get real image tag)
        local manifest_digest
        manifest_digest=$(echo "$tags_response" | jq -r '
            [
                .tags[]
                | select(.name | (contains(".sig") or contains(".att") or contains(".sbom") or contains(".dockerfile")) | not)
                | .manifest_digest
                | select(. != null and . != "")
            ][0] // ""' 2>/dev/null)
        
        if [ "${QUAY_CHECK_DEBUG:-false}" = "true" ]; then
            log_info "      [DEBUG] Manifest digest: ${manifest_digest:-EMPTY}"
            if [ -z "$manifest_digest" ]; then
                log_info "      [DEBUG] Available tags: $(echo "$tags_response" | jq -r '.tags[].name' 2>/dev/null | head -5 | tr '\n' ', ')"
            fi
        fi
        
        if [ -n "$manifest_digest" ] && [ "$manifest_digest" != "null" ] && [ "$manifest_digest" != "empty" ]; then
            QUAY_IMAGE_DIGEST="quay.io/redhat-user-workloads-stage/${namespace}/${component_name}@${manifest_digest}"
            return 0
        fi
    fi
    
    return 1
}

# Force delete a component with finalizer removal if stuck
# Usage: force_delete_component <component_name> <namespace>
force_delete_component() {
    local component_name="$1"
    local namespace="$2"
    local timeout=30  # seconds to wait before forcing
    
    # Try normal deletion first
    kubectl delete component "${component_name}" -n "${namespace}" --ignore-not-found=true &>/dev/null || true
    
    # Wait a bit to see if it deletes normally
    local waited=0
    while [ $waited -lt $timeout ]; do
        if ! kubectl get component "${component_name}" -n "${namespace}" &>/dev/null 2>&1; then
            # Successfully deleted
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    # Still exists after timeout - check if it's stuck in deletion
    local deletion_timestamp=$(kubectl get component "${component_name}" -n "${namespace}" \
        -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
    
    if [ -n "$deletion_timestamp" ]; then
        # Component is stuck in deletion - remove finalizers
        log_info "      ⚠️  Component stuck in deletion, removing finalizers..."
        kubectl patch component "${component_name}" -n "${namespace}" \
            --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
        
        # Wait a moment for deletion to complete
        sleep 2
    fi
    
    # Final check
    if kubectl get component "${component_name}" -n "${namespace}" &>/dev/null 2>&1; then
        log_warning "      ⚠️  Component still exists after forced deletion attempt"
        return 1
    fi
    return 0
}

# Wait for PAC to configure and auto-merge configuration PR if needed
# Args: component_name, component_repo_name
# Returns: 0 if PAC ready, 1 if timeout
wait_for_pac_and_merge_pr() {
    local component_name="$1"
    local component_repo_name="$2"
    local max_wait=120  # 2 minutes (increased for auto-recovery)
    local wait_time=0
    local closed_pr_retries=0
    local max_closed_pr_retries=2
    local last_seen_pr=""
    
    log_info "      ⏳ Waiting for PAC configuration (with auto-recovery)..."
    
    while [ $wait_time -lt $max_wait ]; do
        # Check PAC state
        local pac_state=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
            -o jsonpath='{.metadata.annotations.build\.appstudio\.openshift\.io/status}' 2>/dev/null | \
            jq -r '.pac.state // empty' 2>/dev/null)
        
        if [ "$pac_state" = "enabled" ]; then
            log_info "      ✓ PAC configured (${wait_time}s)"
            
            # CRITICAL: Check for PAC configuration errors in events
            # These indicate PAC is stuck and needs intervention
            local pac_error=$(kubectl get events -n "${NAMESPACE}" \
                --field-selector involvedObject.kind=Component,involvedObject.name="${component_name}" \
                --sort-by='.lastTimestamp' 2>/dev/null | \
                grep "ErrorConfiguringPaCForComponentRepository" | tail -1)
            
            if echo "$pac_error" | grep -q "no history in common"; then
                log_warning "      ⚠️  PAC error detected: branches have no common history"
                log_info "      🔧 Auto-recovery: Deleting conflicting branches and retriggering PAC..."
                
                # Delete konflux-* branches (they have no common history with component branch)
                local deleted_count=0
                while read -r branch_ref; do
                    [ -z "$branch_ref" ] && continue
                    local branch_name=$(echo "$branch_ref" | sed 's#refs/heads/##')
                    if gh api -X DELETE "repos/hacbs-release-tests/${component_repo_name}/git/${branch_ref}" 2>/dev/null; then
                        log_info "         ✓ Deleted branch: ${branch_name}"
                        deleted_count=$((deleted_count + 1))
                    fi
                done < <(gh api "repos/hacbs-release-tests/${component_repo_name}/git/refs" --jq '.[].ref' 2>/dev/null | grep "heads/konflux-" || true)
                
                if [ $deleted_count -gt 0 ]; then
                    log_info "      🔄 Retriggering PAC configuration..."
                    kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                        "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || true
                    
                    # Wait for PAC to recreate PR
                    sleep 10
                    wait_time=$((wait_time + 10))
                    continue
                fi
            fi
            
            # Check if PAC created a configuration PR that needs merging
            local merge_url=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
                -o jsonpath='{.metadata.annotations.build\.appstudio\.openshift\.io/status}' 2>/dev/null | \
                jq -r '.pac."merge-url" // empty' 2>/dev/null)
            
            if [ -z "$merge_url" ]; then
                # PAC is enabled but no PR yet - wait briefly (max 15s)
                if [ $wait_time -lt 15 ]; then
                    sleep 3
                    wait_time=$((wait_time + 3))
                    continue
                else
                    # No PR created after 15s - PAC likely won't create one
                    log_warning "      ⚠️  PAC enabled but no PR created after 15s"
                    return 0
                fi
            fi
            
            if [ -n "$merge_url" ]; then
                # Extract PR number from URL
                local pr_number=$(echo "$merge_url" | grep -oE '[0-9]+$')
                if [ -n "$pr_number" ]; then
                    # Check PR state (OPEN, CLOSED, MERGED)
                    local pr_info=$(gh pr view "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                        --json state,mergeable -q '{state: .state, mergeable: .mergeable}' 2>/dev/null || echo '{"state":"UNKNOWN","mergeable":"UNKNOWN"}')
                    local pr_state=$(echo "$pr_info" | jq -r '.state')
                    local pr_mergeable=$(echo "$pr_info" | jq -r '.mergeable')
                    
                    # Handle CLOSED PRs (failed/cancelled)
                    if [ "$pr_state" = "CLOSED" ]; then
                        # Check if we're seeing the same closed PR repeatedly
                        if [ "$last_seen_pr" = "$pr_number" ]; then
                            closed_pr_retries=$((closed_pr_retries + 1))
                            if [ $closed_pr_retries -ge $max_closed_pr_retries ]; then
                                log_warning "      ⚠️  PR #${pr_number} still CLOSED after ${max_closed_pr_retries} retries - giving up"
                                log_warning "         PAC may be stuck or repo configuration incomplete"
                                return 1
                            fi
                        else
                            closed_pr_retries=1
                        fi
                        last_seen_pr="$pr_number"
                        
                        log_warning "      ⚠️  PR #${pr_number} is CLOSED (failed) - retriggering PAC (attempt ${closed_pr_retries}/${max_closed_pr_retries})"
                        kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                            "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || true
                        sleep 10
                        wait_time=$((wait_time + 10))
                        continue
                    fi
                    
                    # Handle CONFLICTING PRs
                    if [ "$pr_mergeable" = "CONFLICTING" ]; then
                        log_warning "      ⚠️  PR #${pr_number} has conflicts - closing and retriggering"
                        gh pr close "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                            --delete-branch 2>/dev/null || true
                        kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                            "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || true
                        log_info "      ✓ Closed conflicting PR (PAC will regenerate)"
                        sleep 10
                        wait_time=$((wait_time + 10))
                        continue
                    fi
                    
                    # CRITICAL: Clean PR branch before merging
                    # 1. Delete pull-request.yaml (prevents pull-request builds)
                    # 2. Configure push.yaml for the chosen arch mode
                    local arch_desc; arch_desc=$( [ "${BUILD_ARCH_MODE}" = "multi" ] && echo "push-only + multi-arch" || echo "push-only + single-arch" )
                    log_info "      🧹 Customizing PR #${pr_number} (${arch_desc})..."
                    local pr_head_branch=$(gh pr view "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                        --json headRefName -q '.headRefName' 2>/dev/null)
                    
                    if [ -n "$pr_head_branch" ]; then
                        local pr_cleanup="${TEMP_DIR}/pr-cleanup-${component_name}"
                        rm -rf "$pr_cleanup"
                        
                        # Try to clone PR branch with retry (GitHub rate limiting / timing issues)
                        local clone_success=false
                        for clone_attempt in 1 2 3; do
                            if git clone -q --depth 1 --branch "${pr_head_branch}" \
                                "https://${GITHUB_TOKEN}@github.com/hacbs-release-tests/${component_repo_name}.git" \
                                "$pr_cleanup" 2>/dev/null; then
                                clone_success=true
                                break
                            fi
                            [ $clone_attempt -lt 3 ] && sleep 5
                        done
                        
                        if [ "$clone_success" = "true" ]; then
                            cd "$pr_cleanup"
                            local pr_modified=false
                            
                            # Delete pull-request files
                            for pr_file in .tekton/*pull-request*.yaml .tekton/*pull-request*.yml; do
                                if [ -f "$pr_file" ]; then
                                    git rm -f "$pr_file" &>/dev/null
                                    pr_modified=true
                                fi
                            done
                            
                            # Configure push.yaml for the chosen arch mode
                            for push_file in .tekton/*push*.yaml; do
                                if [ -f "$push_file" ]; then
                                    local file_modified=false

                                    if [ "${BUILD_ARCH_MODE}" = "multi" ]; then
                                        # --- Multi-arch: 4 platforms ---
                                        # 1. Add multi-platform annotations (if not present)
                                        if ! grep -q "multi-platform-required" "$push_file"; then
                                            yq eval -i '.metadata.annotations."build.appstudio.openshift.io/multi-platform-required" = "true"' "$push_file"
                                            yq eval -i '.metadata.annotations."build.appstudio.openshift.io/request-platforms" = "linux/amd64,linux/arm64,linux/s390x,linux/ppc64le"' "$push_file"
                                            file_modified=true
                                        fi

                                        # 2. Set build-platforms param (ARRAY — Kueue CEL requires iterable type)
                                        if yq eval '.spec.params[] | select(.name == "build-platforms")' "$push_file" | grep -q "build-platforms"; then
                                            yq eval -i '(.spec.params[] | select(.name == "build-platforms") | .value) = ["linux/x86_64", "linux/arm64", "linux/s390x", "linux/ppc64le"]' "$push_file"
                                        else
                                            yq eval -i '.spec.params += [{"name": "build-platforms", "value": ["linux/x86_64", "linux/arm64", "linux/s390x", "linux/ppc64le"]}]' "$push_file"
                                        fi
                                        file_modified=true

                                        # 3. Ensure build-image-index=true (creates OCI index for multi-arch)
                                        if ! yq eval '.spec.params[] | select(.name == "build-image-index")' "$push_file" | grep -q "build-image-index"; then
                                            yq eval -i '.spec.params += [{"name": "build-image-index", "value": "true"}]' "$push_file"
                                            file_modified=true
                                        fi

                                        # 4. Update pipelineSpec.params defaults
                                        if yq eval '.spec.pipelineSpec.params[] | select(.name == "build-platforms")' "$push_file" | grep -q "build-platforms"; then
                                            yq eval -i '(.spec.pipelineSpec.params[] | select(.name == "build-platforms") | .default) = ["linux/x86_64", "linux/arm64", "linux/s390x", "linux/ppc64le"]' "$push_file"
                                        else
                                            yq eval -i '.spec.pipelineSpec.params += [{"name": "build-platforms", "type": "array", "default": ["linux/x86_64", "linux/arm64", "linux/s390x", "linux/ppc64le"]}]' "$push_file"
                                        fi
                                        if ! yq eval '.spec.pipelineSpec.params[] | select(.name == "build-image-index")' "$push_file" | grep -q "build-image-index"; then
                                            yq eval -i '.spec.pipelineSpec.params += [{"name": "build-image-index", "type": "string", "default": "true"}]' "$push_file"
                                            file_modified=true
                                        fi
                                    fi
                                    # single-arch: PAC default (linux/amd64) is used as-is; no extra annotations needed.

                                    # Keep in-progress runs alive; do not auto-cancel earlier builds.
                                    if [ "$(yq eval '.metadata.annotations."pipelinesascode.tekton.dev/cancel-in-progress" // ""' "$push_file")" != "false" ]; then
                                        yq eval -i '.metadata.annotations."pipelinesascode.tekton.dev/cancel-in-progress" = "false"' "$push_file"
                                        file_modified=true
                                    fi

                                    if [ "$file_modified" = "true" ]; then
                                        git add "$push_file"
                                        pr_modified=true
                                    fi
                                fi
                            done

                            if [ "$pr_modified" = "true" ]; then
                                git config user.name "Large Snapshot Test Bot" 2>/dev/null
                                git config user.email "release-team@redhat.com" 2>/dev/null
                                git commit -q -m "chore: Configure ${arch_desc}" 2>/dev/null
                                git push -q origin "${pr_head_branch}" 2>/dev/null && \
                                    log_info "      ✓ PR customized (${arch_desc})" || \
                                    log_warning "      ⚠️  Failed to push PR customization"
                            fi
                            
                            cd - >/dev/null
                            rm -rf "$pr_cleanup"
                        else
                            log_warning "      ⚠️  Failed to clone PR branch after 3 attempts - using default PAC config"
                            log_warning "         (Build will use single-platform, not multi-arch)"
                        fi
                    fi
                    
                    log_info "      📝 Merging PAC configuration PR #${pr_number}..."
                    
                    # Retry merge with delays (GitHub needs time to process customization commits)
                    local merge_error=""
                    local merge_success=false
                    local max_merge_retries=3
                    
                    for merge_attempt in $(seq 1 $max_merge_retries); do
                        if [ $merge_attempt -gt 1 ]; then
                            log_info "      ⏳ Waiting 5s for PR to become mergeable (attempt ${merge_attempt}/${max_merge_retries})..."
                            sleep 5
                        fi
                        
                        # Try with --admin first (bypasses checks)
                        if merge_error=$(gh pr merge "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                            --merge --admin --delete-branch=false 2>&1); then
                            log_info "      ✓ PR #${pr_number} merged (push-only config)"
                            merge_success=true
                            break
                        # Try without --admin as fallback
                        elif merge_error=$(gh pr merge "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                            --merge --delete-branch=false 2>&1); then
                            log_info "      ✓ PR #${pr_number} merged (without --admin)"
                            merge_success=true
                            break
                        else
                            if [ $merge_attempt -lt $max_merge_retries ]; then
                                log_info "      ⚠️  Merge attempt ${merge_attempt} failed (will retry)"
                            fi
                        fi
                    done
                    
                    if [ "$merge_success" = false ]; then
                        log_warning "      ⚠️  Could not merge PR #${pr_number} after ${max_merge_retries} attempts"
                        log_warning "         Error: ${merge_error}"
                        return 1
                    fi
                fi
            fi
            
            return 0
        fi
        
        sleep 3
        wait_time=$((wait_time + 3))
    done
    
    log_warning "      ⚠️  PAC not configured after ${max_wait}s"
    return 1
}

# Create GitHub branch with PAC configuration for a component
# Usage: ensure_component_repo <component_name> [cleanup_only]
# Args:
#   component_name: Name of the component
#   cleanup_only: If "true", only clean up pull-request files (don't update Dockerfile)
# Returns: 0 if repo exists/created and PAC config updated, 1 if failed
# One repo per component (OCP-style): hacbs-release-tests/rh-adv-large-{component_name}
ensure_component_repo() {
    local component_name="$1"
    local cleanup_only="${2:-false}"
    local component_repo_name="${COMPONENT_REPO_PREFIX}-${component_name}"
    local full_repo="${COMPONENT_REPO_ORG}/${component_repo_name}"
    local component_branch="${COMPONENT_BRANCH_PREFIX}-${component_name}"  # Component-specific branch
    
    # Extract version from component name (e.g., multi-v4-15-apiserver-watcher-01 → v4-15)
    local version=$(echo "$component_name" | grep -oE "v4-[0-9]+" | head -1)
    local app_name="large-snapshot-build-${version}"
    
    # Check if component repo already exists (use cached list from batch query)
    local repo_exists=false
    if echo "${ALL_COMPONENT_REPOS}" | grep -q "^${component_repo_name}$"; then
        repo_exists=true
        log_info "      ✓ Component repo already exists: ${full_repo}"
    fi
    
    # Create repo and push template if it doesn't exist
    if [ "$repo_exists" = false ]; then
        log_info "      Creating component repo with PAC config: ${full_repo}"
        
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local template_dir="${LOCAL_TEMPLATE_DIR:-${script_dir}/../template}"
        local copy_script="${script_dir}/../../scripts/copy-branch-to-repo-git.sh"
        local create_repo_script="${script_dir}/../../scripts/create-github-repo.sh"
        
        # Prefer local template (self-contained, no e2e-base dependency)
        # CRITICAL: Push ONLY Dockerfile (no .tekton/) to avoid conflicts with PAC auto-generation
        if [ -d "$template_dir" ] && [ -f "${template_dir}/Dockerfile" ]; then
            log_info "      Using local template: ${template_dir}"
            # Create repo via API if it doesn't exist
            if ! curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
                "https://api.github.com/repos/${full_repo}" | grep -q '"full_name"'; then
                [ -f "$create_repo_script" ] && "${create_repo_script}" "${full_repo}" 2>/dev/null || true
            fi
            local tmp_push="${TEMP_DIR}/push-${component_name}"
            rm -rf "$tmp_push"
            
            # Copy ONLY Dockerfile (not .tekton/) - let PAC generate .tekton files
            mkdir -p "$tmp_push"
            cp "${template_dir}/Dockerfile" "$tmp_push/"
            
            cd "$tmp_push"
            git init -q
            git config user.name "Large Snapshot Test Bot"
            git config user.email "release-team@redhat.com"
            git add Dockerfile
            git commit -q -m "feat: Initial Dockerfile for ${component_name}"
            git remote add origin "https://${GITHUB_TOKEN}@github.com/${full_repo}.git"
            git push -q -f origin "HEAD:${component_branch}" 2>/dev/null || {
                log_warning "      ⚠️  Failed to push Dockerfile to ${full_repo}"
                return 1
            }
            cd - >/dev/null
        else
            # Fallback: copy from e2e-base branch
            if [ ! -f "$copy_script" ]; then
                log_error "No local template at ${template_dir} and copy-branch-to-repo-git.sh not found"
                return 1
            fi
            local retry_count=0
            local max_retries=3
            local retry_delay=10
            while [ $retry_count -lt $max_retries ]; do
                local error_output=$(mktemp)
                if "${copy_script}" "${BASE_REPO}" "${PAC_TEMPLATE_BRANCH}" "${full_repo}" "${component_branch}" "true" 2>"${error_output}"; then
                    rm -f "${error_output}"
                    break
                else
                    retry_count=$((retry_count + 1))
                    local error_msg=$(cat "${error_output}")
                    rm -f "${error_output}"
                    if echo "$error_msg" | grep -qi "rate limit\|abuse\|403"; then
                        [ $retry_count -lt $max_retries ] && sleep $retry_delay && retry_delay=$((retry_delay * 2)) && continue
                    fi
                    log_warning "      ⚠️  Failed to create repo: ${full_repo}"
                    [ -n "$error_msg" ] && log_warning "      Error: ${error_msg}"
                    return 1
                fi
            done
            [ $retry_count -ge $max_retries ] && log_warning "      ⚠️  Failed after ${max_retries} retries" && return 1
        fi
        log_info "      ✓ Component repo created successfully"
    fi
    
    # Update component repo: Only update Dockerfile (PAC handles .tekton generation)
    log_info "      Updating component repository: ${component_name}"
    local temp_repo="${TEMP_DIR}/repo-${component_name}"
    
    # Try to clone the component-specific branch; if it doesn't exist, create it from main
    if git clone -q --depth 1 --branch "${component_branch}" \
        "https://${GITHUB_TOKEN}@github.com/${full_repo}.git" "${temp_repo}" 2>/dev/null; then
        # Branch exists - update Dockerfile only (clean up pull-request files if PAC already configured)
        
        cd "${temp_repo}"
        
        # If .tekton directory exists, PAC has already configured it
        # Delete any pull-request files (we only want push builds)
        local pac_updated=false
        if [ -d ".tekton" ]; then
            for pr_file in .tekton/*pull-request*.yaml .tekton/*pull-request*.yml; do
                if [ -f "$pr_file" ]; then
                    git rm -f "$pr_file" &>/dev/null || rm -f "$pr_file"
                    log_info "      ✓ Deleted pull-request trigger: $(basename "$pr_file")"
                    pac_updated=true
                fi
            done
        fi
        
        # Generate custom Dockerfile with random size (only if not cleanup_only mode)
        local dockerfile_updated=false
        local size_mb=0
        
        if [ "$cleanup_only" = "true" ]; then
            # Cleanup mode: Don't touch Dockerfile (avoid triggering new builds)
            log_info "      Cleanup mode: Skipping Dockerfile update"
        else
            # Generate custom Dockerfile with random size (300 MB - 1.5 GB)
            # IMPORTANT: Size limit due to build pod memory constraints
            # - Images >1.5 GB trigger OOM kills during buildah commit phase
            # - Tested: 1-5 GB failed, 500 MB-5 GB failed, 300 MB-1.5 GB stable
            # - See README.md "Image Size Limitations" for full explanation
            size_mb=$((300 + RANDOM % 1201))  # Random 300-1500 MB
            log_info "      Generating Dockerfile with size: ${size_mb} MB"
            
            cat > Dockerfile << 'DOCKERFILE_EOF'
FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y python3 python3-pip vim git wget && dnf clean all

# Generate random-sized image (300 MB - 1.5 GB)
# Size constrained by build pod memory to avoid OOM kills during commit
ARG IMAGE_SIZE_MB=900
RUN SIZE_MB=${IMAGE_SIZE_MB} && \
    echo "========================================" && \
    echo "Building large test image: ${SIZE_MB} MB" && \
    echo "========================================" && \
    dd if=/dev/urandom of=/opt/data.bin bs=1M count=${SIZE_MB} 2>/dev/null && \
    echo "Image size: ${SIZE_MB} MB" > /opt/size.txt

WORKDIR /app
COPY . /app/

LABEL test-type="large-snapshot" \
      size-range="300-1500MB"
LABEL konflux.additional-tags="stable"

CMD ["/bin/bash", "-c", "cat /opt/size.txt && tail -f /dev/null"]
DOCKERFILE_EOF
            
            # Set the actual size in the Dockerfile
            sed -i "s|ARG IMAGE_SIZE_MB=2000|ARG IMAGE_SIZE_MB=${size_mb}|g" Dockerfile
            
            git add Dockerfile &>/dev/null || true
            if ! git diff --cached --quiet Dockerfile 2>/dev/null; then
                dockerfile_updated=true
            fi
        fi
        
        # Push changes if there were any (pac cleanup or dockerfile update)
        if [ "$pac_updated" = "true" ] || [ "$dockerfile_updated" = "true" ]; then
            git config user.name "Large Snapshot Test Bot" 2>/dev/null
            git config user.email "release-team@redhat.com" 2>/dev/null
            
            # Add changes (Dockerfile or .tekton cleanup)
            git add -A &>/dev/null
            
            # Check if there are actual changes to commit
            if git diff --cached --quiet; then
                log_info "      ✓ Branch already up to date: ${component_name}"
            else
                # Commit and push
                commit_msg="feat: Update Dockerfile (${size_mb}MB) for ${component_name}"
                if [ "$pac_updated" = "true" ]; then
                    commit_msg="feat: Update config and Dockerfile (${size_mb}MB) for ${component_name}"
                fi
                
                if git commit -q -m "$commit_msg" 2>/dev/null && \
                   git push -q origin "${component_branch}" 2>/dev/null; then
                    log_info "      ✓ Pushed updates (${size_mb}MB): ${component_name}"
                else
                    log_warning "      ⚠️  Failed to push: ${component_name}"
                fi
            fi
        else
            # No changes needed
            log_info "      ✓ Branch already configured: ${component_name}"
        fi

        cd - >/dev/null
        rm -rf "${temp_repo}"
        log_info "      ✓ Repository ready: ${component_name}"
    else
        # Branch doesn't exist - this shouldn't happen (initial push created it)
        log_warning "      ⚠️  Branch doesn't exist (unexpected): ${component_branch}"
        log_warning "      This should have been created during repo initialization"
        return 1
    fi
    
    return 0
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Create temp directory for tracking
TEMP_DIR=$(mktemp -d)
if [ -z "${TEMP_DIR}" ] || [ ! -d "${TEMP_DIR}" ]; then
    echo "❌ ERROR: Failed to create temporary directory" >&2
    echo "   mktemp returned: '${TEMP_DIR}'" >&2
    exit 1
fi

COMPONENT_LIST="${TEMP_DIR}/components.txt"
COMPONENTS_TO_BUILD="${TEMP_DIR}/components-to-build.txt"  # Only components that need builds (for monitoring)

# Initialize files (prevents "No such file" errors when loops don't run)
> "${COMPONENT_LIST}"
> "${COMPONENTS_TO_BUILD}"

# ============================================================================
# Validate Prerequisites
# ============================================================================

log_section "🔍 Validating Prerequisites"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found in PATH"
    exit 1
fi

# Check GITHUB_TOKEN for branch creation
if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN environment variable is required for creating GitHub branches"
    log_error "This token needs 'repo' permissions to create branches in ${BASE_REPO}"
    exit 1
fi

# Verify GITHUB_TOKEN has access to BASE_REPO
log_info "Verifying GITHUB_TOKEN has access to ${BASE_REPO}..."

# SECURITY: Never add -v or -i flags to curl - will leak Authorization header with token
# Capture full API response for debugging
REPO_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${BASE_REPO}" 2>&1)

# Extract HTTP status code
HTTP_CODE=$(echo "${REPO_RESPONSE}" | grep "HTTP_CODE:" | cut -d: -f2)
REPO_JSON=$(echo "${REPO_RESPONSE}" | sed '/HTTP_CODE:/d')

# Extract full_name or error message using jq (preferred)
if command -v jq &>/dev/null; then
    REPO_CHECK=$(echo "${REPO_JSON}" | jq -r '.full_name // empty' 2>/dev/null)
    REPO_ERROR=$(echo "${REPO_JSON}" | jq -r '.message // empty' 2>/dev/null)
else
    # Fallback: grep for full_name without jq
    REPO_CHECK=$(echo "${REPO_JSON}" | grep -o '"full_name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    REPO_ERROR=$(echo "${REPO_JSON}" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
fi

# Check if access was successful
if [ "$HTTP_CODE" = "200" ] && [ -n "$REPO_CHECK" ]; then
    log_info "  ✓ Token has access to ${BASE_REPO}"
elif [ -z "$REPO_CHECK" ]; then
    log_error "GITHUB_TOKEN cannot access repository ${BASE_REPO}"
    log_error "HTTP Status: ${HTTP_CODE:-unknown}"
    if [ -n "$REPO_ERROR" ]; then
        log_error "GitHub API error: ${REPO_ERROR}"
    fi
    log_error "This usually means:"
    log_error "  1. Token doesn't have 'repo' scope"
    log_error "  2. Token doesn't have access to the organization/repository"
    log_error "  3. Repository doesn't exist or was renamed"
    log_error "  4. Token has expired or been revoked"
    log_error ""
    log_error "Check the GitHub token Kubernetes secret in your cluster (default: hacbs-release-tests-token)"
    log_error ""
    log_error "Debug: Raw API response (first 300 chars):"
    log_error "$(echo "${REPO_JSON}" | head -c 300)"
    exit 1
else
    log_info "  ✓ Token has access to ${BASE_REPO}"
fi

# Check namespace exists (this also validates cluster connectivity)
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    log_error "Cannot access namespace '${NAMESPACE}' - check cluster connectivity and permissions"
    exit 1
fi

# Validate component count
if ! [[ "${COMPONENT_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
    log_error "COMPONENT_COUNT must be a positive integer (got: '${COMPONENT_COUNT}')"
    exit 1
fi

# OPTIMIZATION: Fetch all components and pipelineruns once for batch checking
log_info "Fetching existing components and builds (batch query for efficiency)..."
ALL_COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
    -l test.appstudio.openshift.io/type=multi-version-build \
    -o json 2>/dev/null || echo '{"items":[]}')

ALL_PIPELINERUNS_JSON=$(kubectl get pipelinerun -n "${NAMESPACE}" \
    -l pipelines.appstudio.openshift.io/type=build \
    -o json 2>/dev/null || echo '{"items":[]}')

EXISTING_COMPONENT_COUNT=$(echo "${ALL_COMPONENTS_JSON}" | jq '.items | length')

# OPTIMIZATION: Fetch all component repos once (one repo per component, OCP-style)
log_info "Fetching existing component repos (batch query to reduce API calls)..."
ALL_COMPONENT_REPOS=""
for page in 1 2 3 4 5; do
    page_raw=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/orgs/${COMPONENT_REPO_ORG}/repos?per_page=100&page=${page}&type=all" 2>/dev/null | \
        jq -r '.[].name' 2>/dev/null || echo "")
    page_repos=$(echo "${page_raw}" | grep "^${COMPONENT_REPO_PREFIX}-" 2>/dev/null || true)
    ALL_COMPONENT_REPOS="${ALL_COMPONENT_REPOS}${page_repos}"$'\n'
    
    raw_count=$(echo "${page_raw}" | grep -c . 2>/dev/null || echo 0)
    if [ "${raw_count}" -lt 100 ]; then
        break
    fi
done
log_info "  Found $(echo "$ALL_COMPONENT_REPOS" | grep -c "^${COMPONENT_REPO_PREFIX}-" 2>/dev/null || echo 0) component repos"

# Count components with successful builds (reusable images) - using in-memory data
EXISTING_WITH_BUILDS=0
EXISTING_IMAGES_LIST=()
if [ ${EXISTING_COMPONENT_COUNT} -gt 0 ]; then
    log_info "Checking existing components for reusable builds..."
    while read -r comp_name; do
        # Check container image from in-memory component data
        promoted_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
            ".items[] | select(.metadata.name == \"${comp_name}\") | .status.lastPromotedImage // \"\"")
        
        has_build=false
        # Check status.lastPromotedImage (Konflux integration-service sets this after build)
        if [ -n "${promoted_image}" ] && [ "${promoted_image}" != "null" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
            has_build=true
        else
            # Fallback: Check PipelineRuns from in-memory data (for builds not yet promoted)
            plr_success=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${comp_name}" '
                [
                    .items[]
                    | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                    | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
                    | .metadata.name
                ][0] // ""')
            
            if [ -n "${plr_success}" ]; then
                has_build=true
            fi
        fi
        
        if [ "${has_build}" = "true" ]; then
            EXISTING_WITH_BUILDS=$((EXISTING_WITH_BUILDS + 1))
            # Store first 5 component names for display
            if [ ${#EXISTING_IMAGES_LIST[@]} -lt 5 ]; then
                EXISTING_IMAGES_LIST+=("${comp_name}")
            fi
        fi
    done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')
    
    log_info "  (Used 2 Kubernetes API calls instead of $((EXISTING_COMPONENT_COUNT * 3)))"
fi

if [ ${EXISTING_COMPONENT_COUNT} -gt 0 ]; then
    echo "" >&2
    log_info "📊 Existing components in namespace:"
    log_info "   Total components: ${EXISTING_COMPONENT_COUNT}"
    log_info "   With successful builds: ${EXISTING_WITH_BUILDS}"
    log_info "   Without builds (zombies): $((EXISTING_COMPONENT_COUNT - EXISTING_WITH_BUILDS))"
    
    if [ ${EXISTING_WITH_BUILDS} -gt 0 ]; then
        log_info "   Sample components with builds:"
        for comp in "${EXISTING_IMAGES_LIST[@]}"; do
            log_info "     • ${comp}"
        done
        if [ ${EXISTING_WITH_BUILDS} -gt 5 ]; then
            log_info "     ... and $((EXISTING_WITH_BUILDS - 5)) more"
        fi
    fi
    echo "" >&2
fi

# Handle FORCE_REBUILD: Delete ALL existing components to start fresh
if [ "${FORCE_REBUILD}" = "true" ] && [ ${EXISTING_COMPONENT_COUNT} -gt 0 ]; then
    log_warning ""
    log_warning "🔄 FORCE_REBUILD=true: Deleting ALL existing components (including valid ones)"
    log_warning "   This will rebuild all ${COMPONENT_COUNT} components from scratch"
    log_info "   Deleting ${EXISTING_COMPONENT_COUNT} existing components..."
    echo "" >&2
    
    DELETED_COUNT=0
    while read -r comp_name; do
        log_info "   🗑️  Deleting: ${comp_name}"
        force_delete_component "${comp_name}" "${NAMESPACE}"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')
    
    log_info "   ✅ Deleted ${DELETED_COUNT} components"
    log_info "   Will create ${COMPONENT_COUNT} fresh components"
    echo "" >&2
    
    # Reset counters after deletion
    EXISTING_COMPONENT_COUNT=0
    EXISTING_WITH_BUILDS=0
fi

# Configuration limits
MAX_TOTAL_COMPONENTS=${COMPONENT_COUNT}  # Target total components from argument
BATCH_SIZE=2                             # Issue builds in pairs (2 components = 1 pair of builds)
BATCH_DELAY=600                          # 10 minutes between pairs (600 seconds)

# Calculate how many components to create this run
# IMPORTANT: Only count components WITH builds toward target (zombies don't count)
SKIP_CREATION=false
if [ ${EXISTING_WITH_BUILDS} -ge ${MAX_TOTAL_COMPONENTS} ]; then
    # Already have enough VALID components (with builds)
    log_warning "Already have ${EXISTING_WITH_BUILDS} valid components (target: ${MAX_TOTAL_COMPONENTS})"
    log_info "   No new components will be created this run"
    log_info "   Script will verify existing images and patch digests"
    SKIP_CREATION=true
else
    # Calculate how many more we need to reach target (based on VALID components only)
    NEEDED=$((MAX_TOTAL_COMPONENTS - EXISTING_WITH_BUILDS))
    log_info "Will create components until reaching ${MAX_TOTAL_COMPONENTS} valid builds"
    log_info "   Existing valid: ${EXISTING_WITH_BUILDS} components with builds"
    log_info "   Zombies: $((EXISTING_COMPONENT_COUNT - EXISTING_WITH_BUILDS)) (will be deleted/rebuilt)"
    log_info "   Needed: ${NEEDED} more to reach target"
fi

log_success "Prerequisites validated"
log_info "   Cluster: $(kubectl config current-context)"
log_info "   Namespace: ${NAMESPACE}"
log_info "   Total components: ${COMPONENT_COUNT}"
log_info "   Product versions: ${PRODUCT_VERSIONS}"
log_info "   Components/version: ~$((COMPONENT_COUNT / PRODUCT_VERSIONS)) (last version gets remainder)"
if [ "${FORCE_REBUILD}" = "true" ]; then
    log_info "   🔄 Force rebuild: ENABLED (all existing components deleted, fresh start)"
else
    log_info "   ➕ Incremental mode: ENABLED (preserve valid, add missing to reach ${COMPONENT_COUNT})"
fi
if [ "${DISABLE_QUAY_REUSE}" = "true" ]; then
    log_info "   🚫 Quay search: DISABLED (rebuild invalid components without checking Quay)"
else
    log_info "   🔍 Quay search: ENABLED (check Quay for salvageable images for invalid components)"
fi
echo "" >&2
log_info "🎯 Multi-Version Strategy:"
log_info "   Building ${PRODUCT_VERSIONS} different product versions (e.g., 4.15, 4.16, etc.)"
log_info "   Each version has ~$((COMPONENT_COUNT / PRODUCT_VERSIONS)) components (last version gets remainder)"
log_info "   This mirrors actual production release patterns for accurate testing"

# Note: Component creation is skipped via if statement below when SKIP_CREATION=true

# ============================================================================
# Step 1: Create Application
# ============================================================================

# Skip creation if we already have enough components
if [ "${SKIP_CREATION}" = "true" ]; then
    log_section "✅ Skipping Creation Steps"
    log_info "Already have ${EXISTING_WITH_BUILDS} valid components (target: ${MAX_TOTAL_COMPONENTS})"
    log_info "Building component list from existing components for digest extraction..."
    echo "" >&2
    
    # Populate COMPONENT_LIST with existing components
    > "${COMPONENT_LIST}"
    while read -r comp_name; do
        # Get application name for this component
        app_name=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
            ".items[] | select(.metadata.name == \"${comp_name}\") | .metadata.labels[\"appstudio.application\"] // \"\"")
        if [ -n "${app_name}" ]; then
            echo "${comp_name}:${app_name}" >> "${COMPONENT_LIST}"
        fi
    done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')
    
    log_info "Added ${EXISTING_WITH_BUILDS} existing components to list"
    echo "" >&2
else
    log_section "📦 Step 1/5: Creating Applications (Multi-Version)"
    log_info "Creating ${PRODUCT_VERSIONS} product versions (~$((COMPONENT_COUNT / PRODUCT_VERSIONS)) each, last gets remainder)"
    log_info "This mirrors real-world production release scenarios"
    echo "" >&2

# Calculate per-version component distribution:
#   rest = total mod PRODUCT_VERSIONS
#   versions 1..(N-1): VERSION_COMPONENT_COUNT = (total - rest) / PRODUCT_VERSIONS
#   last version  (N): VERSION_COMPONENT_COUNT = base + rest
# This guarantees sum == COMPONENT_COUNT with even distribution.
_CPV_REST=$((COMPONENT_COUNT % PRODUCT_VERSIONS))
_CPV_BASE=$(( (COMPONENT_COUNT - _CPV_REST) / PRODUCT_VERSIONS ))

# Create applications for each product version
for (( v=0; v<PRODUCT_VERSIONS; v++ )); do
    VERSION_PATTERN="${VERSION_PATTERNS[$v]}"
    # Replace dots with hyphens for Kubernetes naming compliance
    VERSION_SAFE="${VERSION_PATTERN//./-}"
    APP_NAME="${APP_PREFIX}-v${VERSION_SAFE}"

    # Last version absorbs the remainder so all slots sum to exactly COMPONENT_COUNT
    if [ $((v + 1)) -eq "${PRODUCT_VERSIONS}" ]; then
        VERSION_COMPONENT_COUNT=$(( _CPV_BASE + _CPV_REST ))
    else
        VERSION_COMPONENT_COUNT=${_CPV_BASE}
    fi
    
    log_info "Ensuring Application exists: ${APP_NAME}"
    log_info "  Version: ${VERSION_PATTERN}"
    log_info "  Will scan components 01-${VERSION_COMPONENT_COUNT} (to find all existing)"
    
    if ! kubectl apply -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    test.appstudio.openshift.io/type: "multi-version-build"
    test.appstudio.openshift.io/version: "${VERSION_PATTERN}"
    test.appstudio.openshift.io/purpose: "worst-case-signing-test"
  annotations:
    description: "Version ${VERSION_PATTERN} - scanning up to ${VERSION_COMPONENT_COUNT} component names for worst-case signing test"
spec:
  displayName: "Version ${VERSION_PATTERN} Dummy Build - Multi-Component"
EOF
    then
        log_error "Failed to create/update application: ${APP_NAME}"
        log_error "  This may indicate namespace permissions issue or API server problem"
        exit 1
    fi
    
    # Track application name and component count
    echo "${APP_NAME}:${VERSION_COMPONENT_COUNT}" >> "${TEMP_DIR}/applications.txt"
done

echo "" >&2
log_success "Created ${PRODUCT_VERSIONS} product version applications"

# ============================================================================
# Step 2: Create Components (Realistic naming)
# ============================================================================

log_section "🔨 Step 2/5: Creating Components"
log_info "Creating components with realistic naming patterns"
log_info "Base repository: ${BASE_GITHUB_URL}"
echo "" >&2

# Component name patterns - realistic component types
COMPONENT_PATTERNS=(
    "apiserver-watcher"
    "image-service"
    "installer"
    "installer-agent"
    "installer-controller"
    "assisted-service"
    "storage-driver"
    "storage-driver-operator"
    "machine-installer"
    "machine-operator"
    "runtime-config"
    "cli"
    "cli-artifacts"
    "credential-operator"
    "authentication-operator"
    "autoscaler"
    "autoscaler-operator"
    "machine-operator"
    "bootstrap"
    "config-operator"
    "etcd-operator"
    "api-operator"
    "machine-approver"
    "monitoring-operator"
    "network-operator"
    "tuning-operator"
)

created_count=0
total_components=0
skipped_count=0
quay_reused_count=0
cannot_verify_count=0  # Zombies we couldn't verify (possible private repo)
actual_new_count=0  # Track ACTUAL new components created (not reused)

# Iterate through each application (product version)
while IFS=: read -r app_name component_count; do
    [ -z "$app_name" ] && continue
    
    # Extract version from app name (with hyphens, not dots for k8s compliance)
    version=$(echo "$app_name" | grep -oP 'v\K[0-9.-]+')
    
    log_info "Scanning components 01-${component_count} for version ${version} (reuse existing, create missing)..."
    
    # Create components for this version (in batches)
    for (( i=1; i<=component_count; i++ )); do
        # Refresh cache periodically to detect completed builds and avoid false zombie detection
        # Refresh every 10 components to balance freshness vs API overhead
        if [ $((i % 10)) -eq 0 ] && [ $i -gt 1 ]; then
            log_info "   🔄 Refreshing cache (every 10 components) to detect completed builds..."
            ALL_COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
                -l test.appstudio.openshift.io/type=multi-version-build \
                -o json 2>/dev/null || echo '{"items":[]}')
            ALL_PIPELINERUNS_JSON=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                -l pipelines.appstudio.openshift.io/type=build \
                -o json 2>/dev/null || echo '{"items":[]}')
            
            # Recount EXISTING_WITH_BUILDS with fresh data
            EXISTING_WITH_BUILDS=0
            while read -r comp_name; do
                # Konflux uses .status.lastPromotedImage (NOT .status.containerImage)
                promoted_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
                    ".items[] | select(.metadata.name == \"${comp_name}\") | .status.lastPromotedImage // \"\"")
                
                # Check lastPromotedImage
                if [ -n "${promoted_image}" ] && [ "${promoted_image}" != "null" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
                    EXISTING_WITH_BUILDS=$((EXISTING_WITH_BUILDS + 1))
                else
                    # Fallback: Check PipelineRuns (for builds not yet promoted)
                    plr_success=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${comp_name}" '
                        [
                            .items[]
                            | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                            | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
                            | .metadata.name
                        ][0] // ""')
                    
                    if [ -n "${plr_success}" ]; then
                        EXISTING_WITH_BUILDS=$((EXISTING_WITH_BUILDS + 1))
                    fi
                fi
            done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')
            
            log_info "   📊 Cache refreshed: ${EXISTING_WITH_BUILDS} components with successful builds"
        fi
        
        # Check if we've reached limits
        # Priority 1: Stop if we've reached the target total (200 VALID components WITH successful builds)
        # IMPORTANT: Count only components with SUCCESSFUL builds, not zombies or in-progress!
        # EXISTING_WITH_BUILDS is refreshed after batch delays and includes newly completed builds
        # Do NOT count created_count here - those might be zombies without builds yet
        VALID_COMPONENTS_COUNT=$((EXISTING_WITH_BUILDS + quay_reused_count))
        
        if [ ${VALID_COMPONENTS_COUNT} -ge ${MAX_TOTAL_COMPONENTS} ]; then
            log_info "   ⏸️  Reached target total of ${MAX_TOTAL_COMPONENTS} valid components (current: ${VALID_COMPONENTS_COUNT}), stopping"
            break
        fi
        
        # Use realistic component name pattern (cycle through patterns)
        pattern_idx=$(( (i - 1) % ${#COMPONENT_PATTERNS[@]} ))
        base_component_name="${COMPONENT_PATTERNS[$pattern_idx]}"
        
        # Stable component name (no timestamp) for reuse across test runs
        component_name="${COMPONENT_NAME_PREFIX}-v${version}-${base_component_name}-$(printf '%02d' $i)"
        quay_already_checked=false  # Track if we already checked Quay for this component
        
        # Check if component already exists with successful build
        # Use cached data from initial batch query for efficiency
        # CRITICAL: Konflux uses .status.lastPromotedImage (NOT .status.containerImage which is always null)
        promoted_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
            ".items[] | select(.metadata.name == \"${component_name}\") | .status.lastPromotedImage // \"\"")
        
        has_existing_build=false
        # Check status.lastPromotedImage (Konflux integration-service sets this after build)
        if [ -n "${promoted_image}" ] && [ "${promoted_image}" != "null" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
            has_existing_build=true
        else
            # Fallback: Check PipelineRuns from cached data (for builds that haven't been promoted yet)
            plr_success=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${component_name}" '
                [
                    .items[]
                    | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                    | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
                    | .metadata.name
                ][0] // ""')
            
            if [ -n "${plr_success}" ]; then
                # Found successful PipelineRun - but when DISABLE_QUAY_REUSE=true (force rebuild mode),
                # verify the image actually exists before marking as "has build"
                # This prevents reusing components where the image was garbage collected
                if [ "${DISABLE_QUAY_REUSE:-false}" = "true" ]; then
                    # In force rebuild mode: verify image exists on Quay
                    QUAY_IMAGE_DIGEST=""
                    if check_quay_image_exists "${component_name}" "${NAMESPACE}"; then
                        has_existing_build=true
                        quay_already_checked=true
                    else
                        # PipelineRun succeeded but image gone - treat as zombie
                        has_existing_build=false
                        quay_already_checked=true
                    fi
                else
                    # Normal mode: trust PipelineRun success
                    has_existing_build=true
                fi
            else
                # Final fallback: Check Quay if integration-service and PipelineRuns both unavailable
                # This handles cases where integration-service is broken and PAC garbage-collected old runs
                if [ "${DISABLE_QUAY_REUSE:-false}" != "true" ]; then
                    QUAY_IMAGE_DIGEST=""
                    if check_quay_image_exists "${component_name}" "${NAMESPACE}"; then
                        has_existing_build=true
                        quay_already_checked=true  # Mark that we checked Quay for this component
                    fi
                fi
            fi
        fi
        
        if [ "${has_existing_build}" = "true" ]; then
            log_info "   ♻️  Reusing existing build: ${component_name}"
            
            # Cleanup only: Remove pull-request files without updating Dockerfile (avoid triggering new builds)
            ensure_component_repo "${component_name}" "true" || log_warning "   ⚠️  Failed to clean up repo for ${component_name}"
            
            echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
            skipped_count=$((skipped_count + 1))
            total_components=$((total_components + 1))
            continue
        fi
        
        # Check if component exists
        if kubectl get component "${component_name}" -n "${NAMESPACE}" &>/dev/null; then
            # Use jq to read status.lastPromotedImage and spec.secret
            comp_json=$(kubectl get component "${component_name}" -n "${NAMESPACE}" -o json 2>/dev/null)
            promoted_image=$(echo "$comp_json" | jq -r '.status.lastPromotedImage // ""')
            spec_secret=$(echo "$comp_json" | jq -r '.spec.secret // ""')
            
            log_info "   🔍 Component ${component_name} - lastPromotedImage: ${promoted_image:-'<empty>'}, secret: ${spec_secret:-'<empty>'}"
            
            # Check if component is missing the secret field - if so, delete and recreate
            if [ -z "${spec_secret}" ]; then
                log_warning "   🔧 Component ${component_name} exists but missing secret field, deleting for recreation..."
                
                # Delete existing component (will be recreated below with proper secret)
                force_delete_component "${component_name}" "${NAMESPACE}"
                
                # Don't continue with component existence checks - treat as if component doesn't exist
                # This allows fall-through to component creation logic below
            else
                # Component has secret field - proceed with normal reuse/zombie checks
                
                # If has status.lastPromotedImage with digest, component is valid - reuse it
                if [ -n "${promoted_image}" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
                # Normal reuse path
                discovered_annotation=$(echo "$comp_json" | jq -r '.metadata.annotations["test.appstudio.openshift.io/discovered-from-quay"] // ""')
                if [ "${discovered_annotation}" != "true" ]; then
                    timeout 30s kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                        test.appstudio.openshift.io/discovered-from-quay=true \
                        test.appstudio.openshift.io/reused-image=true \
                        --overwrite &>/dev/null || {
                        log_warning "      ⚠️  Failed to annotate ${component_name} (timeout/error), continuing..."
                    }
                fi
                
                log_info "   ♻️  Reusing image from spec: ${component_name}"
                
                # Cleanup only: Remove pull-request files without updating Dockerfile
                ensure_component_repo "${component_name}" "true" || log_warning "   ⚠️  Failed to clean up repo for ${component_name}"
                
                echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}" || {
                    echo "❌ ERROR: Failed to write to COMPONENT_LIST" >&2
                    echo "   File: ${COMPONENT_LIST}" >&2
                    echo "   Component: ${component_name}" >&2
                    echo "   App: ${app_name}" >&2
                    exit 1
                }
                
                skipped_count=$((skipped_count + 1))
                total_components=$((total_components + 1))
                continue
            fi
            
            # Component exists but is a zombie (no successful build, not from Quay)
            # Check Quay.io BEFORE deleting - might be able to salvage it
            QUAY_IMAGE_DIGEST=""
            quay_already_checked=true  # Mark that we've checked Quay for this component
            
            # DISABLE_QUAY_REUSE: Force fresh builds (for /build-large-snapshot)
            if [ "${DISABLE_QUAY_REUSE:-false}" = "true" ]; then
                quay_check_result=1  # Force "not found"
            else
                check_quay_image_exists "${component_name}" "${NAMESPACE}"
                quay_check_result=$?
            fi
            
            if [ "$quay_check_result" -eq 0 ]; then
                # Image exists on Quay! Delete and recreate with correct image
                log_info "   🔄 Recreating zombie component with Quay image: ${component_name}"
                
                # Define component-specific branch
                component_branch="${COMPONENT_BRANCH_PREFIX}-${component_name}"
                
                # Delete existing component (cleaner than patching)
                force_delete_component "${component_name}" "${NAMESPACE}"
                
                # Create GitHub branch for consistency (required for PipelineRuns)
                if ! ensure_component_repo "${component_name}"; then
                    log_error "   ❌ Failed to create GitHub branch for salvaged zombie: ${component_name}, skipping..."
                    continue
                fi
                
                # Create fresh component with correct image
                kubectl create -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  name: ${component_name}
  namespace: ${NAMESPACE}
  labels:
    appstudio.application: ${app_name}
    test.appstudio.openshift.io/type: "multi-version-build"
    test.appstudio.openshift.io/version: "${version}"
  annotations:
    test.appstudio.openshift.io/discovered-from-quay: "true"
    git-provider: github
    image-controller.appstudio.redhat.com/skip-repository-deletion: "true"
    build.appstudio.openshift.io/request: configure-pac
    build.appstudio.openshift.io/pipeline: >-
      {"name": "${_BUILD_PIPELINE_NAME}",
      "bundle": "${_BUILD_PIPELINE_BUNDLE}"}
    test.appstudio.openshift.io/reused-image: "true"
spec:
  application: ${app_name}
  componentName: ${component_name}
  secret: pipelines-as-code-secret
  containerImage: "${QUAY_IMAGE_DIGEST}"
  source:
    git:
      url: https://github.com/${COMPONENT_REPO_ORG}/${COMPONENT_REPO_PREFIX}-${component_name}
      revision: ${component_branch}
EOF

                # Wait for PAC to create the service account (even though we're reusing image, PAC may trigger builds)
                service_account_name="build-pipeline-${component_name}"
                wait_time=0
                max_wait=60
                while [ $wait_time -lt $max_wait ]; do
                    if kubectl get serviceaccount "${service_account_name}" -n "${NAMESPACE}" &>/dev/null; then
                        break
                    fi
                    sleep 2
                    wait_time=$((wait_time + 2))
                done
                
                echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
                # Don't increment created_count - semantically this is "reuse" not "create"
                quay_reused_count=$((quay_reused_count + 1)) # Image reused from Quay
                skipped_count=$((skipped_count + 1))        # No build needed
                total_components=$((total_components + 1))
                # Don't increment actual_new_count - no new BUILD happened (zombie salvaged with existing image)
                continue
            elif [ "$quay_check_result" -eq 2 ]; then
                # Cannot verify Quay (403/404/network error) - don't delete
                log_warning "   ⚠️  Cannot verify Quay for ${component_name} (HTTP 403/404 or network error)"
                log_warning "      Possible causes: private repo, wrong registry, or insufficient auth"
                log_warning "      Skipping deletion to avoid removing valid component"
                
                # Without branch, component cannot trigger PipelineRuns
                if ! ensure_component_repo "${component_name}"; then
                    log_error "   ❌ Failed to create GitHub branch for unverifiable component: ${component_name}, skipping..."
                    continue
                fi
                
                echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
                cannot_verify_count=$((cannot_verify_count + 1))
                skipped_count=$((skipped_count + 1))
                total_components=$((total_components + 1))
                continue
            else
                # No image on Quay (got 200 but no tags) - but check if build is running first!
                # Don't delete components with running builds
                running_build=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${component_name}" '
                    [
                        .items[]
                        | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                        | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "Unknown"))
                        | .metadata.name
                    ][0] // ""')
                
                if [ -n "${running_build}" ]; then
                    log_info "   ⏳ Component has running build, keeping: ${component_name} (${running_build})"
                    echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
                    skipped_count=$((skipped_count + 1))
                    total_components=$((total_components + 1))
                    continue
                fi
                
            # No image on Quay (got 200 but no tags) - check if PAC is stuck before deleting
            log_warning "   ⚠️  No image found for zombie: ${component_name}"
            
            # CRITICAL: Check if PAC has errors (no common history, failed PRs, etc.)
            # If so, attempt auto-recovery before deleting component
            pac_error=$(kubectl get events -n "${NAMESPACE}" \
                --field-selector involvedObject.kind=Component,involvedObject.name="${component_name}" \
                --sort-by='.lastTimestamp' 2>/dev/null | \
                grep "ErrorConfiguringPaCForComponentRepository" | tail -1 || true)
            
            pac_status=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
                -o jsonpath='{.metadata.annotations.build\.appstudio\.openshift\.io/status}' 2>/dev/null)
            pac_state=$(echo "$pac_status" | jq -r '.pac.state // empty' 2>/dev/null)
            merge_url=$(echo "$pac_status" | jq -r '.pac."merge-url" // empty' 2>/dev/null)
            
            # Auto-recovery for PAC errors
            if [ -n "$pac_error" ] && echo "$pac_error" | grep -q "no history in common"; then
                log_warning "   🔧 Auto-recovery: PAC 'no common history' error detected"
                component_repo_name="${COMPONENT_REPO_PREFIX}-${component_name}"
                
                # Delete conflicting branches
                deleted_count=0
                while read -r branch_ref; do
                    [ -z "$branch_ref" ] && continue
                    branch_name=$(echo "$branch_ref" | sed 's#refs/heads/##')
                    if gh api -X DELETE "repos/hacbs-release-tests/${component_repo_name}/git/${branch_ref}" 2>/dev/null; then
                        log_info "      ✓ Deleted conflicting branch: ${branch_name}"
                        deleted_count=$((deleted_count + 1))
                    fi
                done < <(gh api "repos/hacbs-release-tests/${component_repo_name}/git/refs" --jq '.[].ref' 2>/dev/null | grep "heads/konflux-" || true)
                
                if [ $deleted_count -gt 0 ]; then
                    log_info "   🔄 Retriggering PAC configuration..."
                    kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                        "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || true
                    
                    # Add to reprocess list (don't delete)
                    log_info "   ♻️  Component will be reprocessed: ${component_name}"
                    continue
                fi
            fi
            
            # Check for CLOSED/failed PAC PRs
            if [ "$pac_state" = "enabled" ] && [ -n "$merge_url" ]; then
                pr_number=$(echo "$merge_url" | grep -oE '[0-9]+$')
                if [ -n "$pr_number" ]; then
                    component_repo_name="${COMPONENT_REPO_PREFIX}-${component_name}"
                    pr_state=$(gh pr view "$pr_number" --repo "hacbs-release-tests/${component_repo_name}" \
                        --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
                    
                    if [ "$pr_state" = "CLOSED" ]; then
                        log_warning "   🔧 Auto-recovery: PR #${pr_number} is CLOSED (failed)"
                        log_info "   🔄 Retriggering PAC configuration..."
                        kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                            "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || true
                        
                        # Add to reprocess list (don't delete)
                        log_info "   ♻️  Component will be reprocessed: ${component_name}"
                        continue
                    fi
                fi
            fi
            
            # No auto-recovery possible - delete the zombie component
            log_warning "   🗑️  Deleting zombie component (no image, no recovery): ${component_name}"
            force_delete_component "${component_name}" "${NAMESPACE}"
            # Don't check Quay again - we just checked and it wasn't there
            # Set flag to skip redundant Quay check and proceed directly to component creation
            quay_already_checked=true
            # Fall through to build trigger (will skip Quay check and create new component)
            fi
            fi  # End of "else" block for secret field check
        fi  # End of "if kubectl get component" block
        
        # Check if image already exists on Quay.io (only if component didn't exist before)
        # Skip this if we already checked Quay in the zombie block above
        # DISABLE_QUAY_REUSE: Skip Quay check for fresh builds (for /build-large-snapshot)
        if [ "${quay_already_checked}" = "false" ] && [ "${DISABLE_QUAY_REUSE:-false}" != "true" ]; then
            QUAY_IMAGE_DIGEST=""
            if check_quay_image_exists "${component_name}" "${NAMESPACE}"; then
                # Image exists! Create component pointing to it (no build needed)
                log_info "   ✨ Found existing image on Quay: ${component_name}"
                
                # Define component-specific branch
                component_branch="${COMPONENT_BRANCH_PREFIX}-${component_name}"
                
                # Step 1: Create component first (without branch - avoids race condition)
                echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
                
                kubectl create -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  name: ${component_name}
  namespace: ${NAMESPACE}
  labels:
    appstudio.application: ${app_name}
    test.appstudio.openshift.io/type: "multi-version-build"
    test.appstudio.openshift.io/version: "${version}"
  annotations:
    test.appstudio.openshift.io/discovered-from-quay: "true"
    git-provider: github
    image-controller.appstudio.redhat.com/skip-repository-deletion: "true"
    build.appstudio.openshift.io/request: configure-pac
    build.appstudio.openshift.io/pipeline: >-
      {"name": "${_BUILD_PIPELINE_NAME}",
      "bundle": "${_BUILD_PIPELINE_BUNDLE}"}
    test.appstudio.openshift.io/reused-image: "true"
spec:
  application: ${app_name}
  componentName: ${component_name}
  secret: pipelines-as-code-secret
  containerImage: "${QUAY_IMAGE_DIGEST}"
  source:
    git:
      url: https://github.com/${COMPONENT_REPO_ORG}/${COMPONENT_REPO_PREFIX}-${component_name}
      revision: ${component_branch}
EOF

                # Wait for PAC to create the service account
                service_account_name="build-pipeline-${component_name}"
                wait_time=0
                max_wait=60
                while [ $wait_time -lt $max_wait ]; do
                    if kubectl get serviceaccount "${service_account_name}" -n "${NAMESPACE}" &>/dev/null; then
                        break
                    fi
                    sleep 2
                    wait_time=$((wait_time + 2))
                done
                
                # Step 2: Create GitHub branch now that component exists
                if ! ensure_component_repo "${component_name}"; then
                    log_error "   ❌ Failed to create GitHub branch for Quay-discovered component: ${component_name}"
                fi
                
                # Component object was created, but we're REUSING an existing image from Quay
                quay_reused_count=$((quay_reused_count + 1)) # Image reused from Quay
                skipped_count=$((skipped_count + 1))        # No build needed (semantically "reused")
                total_components=$((total_components + 1))
                # Don't increment created_count - semantically this is "reuse" not "create"
                # Don't increment actual_new_count - no new BUILD happened (image already existed)
                continue
            fi
        fi
        
        # Image doesn't exist - create component FIRST, then branch, then trigger PAC
        # Step 1: Create component WITHOUT configure-pac (avoid Error 75)
        # We'll trigger configure-pac manually right after creation
        # Add unique timestamp to force fresh build (no cache reuse)
        unique_id="$(date +%s)-${version}-${i}"
        
        # Define component-specific branch
        component_branch="${COMPONENT_BRANCH_PREFIX}-${component_name}"
        
        # No annotation initially - will add configure-pac after creation
        BUILD_ANNOTATION=""
        
        kubectl create -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  name: ${component_name}
  namespace: ${NAMESPACE}
  labels:
    appstudio.application: ${app_name}
    test.appstudio.openshift.io/type: "multi-version-build"
    test.appstudio.openshift.io/version: "${version}"
    test.appstudio.openshift.io/build-id: "${unique_id}"
    test.appstudio.openshift.io/component-type: "${base_component_name}"
  annotations:
    git-provider: github
    image.redhat.com/generate: "{\"visibility\": \"public\"}"
    image-controller.appstudio.redhat.com/skip-repository-deletion: "true"
    test.appstudio.openshift.io/fresh-build: "true"
    test.appstudio.openshift.io/pac-branch: "${component_branch}"
    build.appstudio.openshift.io/request: configure-pac
    build.appstudio.openshift.io/pipeline: >-
      {"name": "${_BUILD_PIPELINE_NAME}",
      "bundle": "${_BUILD_PIPELINE_BUNDLE}"}
${_ARCH_ANNOTATIONS}
spec:
  application: ${app_name}
  componentName: ${component_name}
  secret: pipelines-as-code-secret
  containerImage: "quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}"
  source:
    git:
      context: ./
      dockerfileUrl: Dockerfile
      revision: ${component_branch}
      url: https://github.com/${COMPONENT_REPO_ORG}/${COMPONENT_REPO_PREFIX}-${component_name}
EOF

        created_count=$((created_count + 1))
        total_components=$((total_components + 1))
        actual_new_count=$((actual_new_count + 1))  # Count this as "new" (we built it)
        
        # Wait for PAC to create the service account (avoids "serviceaccount not found" errors)
        service_account_name="build-pipeline-${component_name}"
        log_info "   ⏳ Waiting for service account: ${service_account_name}"
        wait_time=0
        max_wait=60
        while [ $wait_time -lt $max_wait ]; do
            if kubectl get serviceaccount "${service_account_name}" -n "${NAMESPACE}" &>/dev/null; then
                log_info "   ✓ Service account ready (${wait_time}s)"
                break
            fi
            sleep 2
            wait_time=$((wait_time + 2))
        done
        
        if [ $wait_time -ge $max_wait ]; then
            log_warning "   ⚠️  Service account not ready after ${max_wait}s, continuing anyway..."
        fi
        
        # Step 2: Create GitHub branch with PAC configuration
        # Now that component exists, create the branch (PAC webhook will fire but component exists)
        if ! ensure_component_repo "${component_name}"; then
            log_error "   ❌ Failed to create/update GitHub branch for ${component_name}, skipping build trigger..."
        else
            log_info "   ✓ GitHub branch ready"
            
            # Step 3: Manually trigger PAC configuration (avoid Error 75 from initial annotation)
            log_info "   📝 Triggering PAC configuration..."
            kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                "build.appstudio.openshift.io/request=configure-pac" --overwrite &>/dev/null || \
                log_warning "   ⚠️  Failed to annotate with configure-pac"
            
            # Step 4: Wait for PAC and auto-merge configuration PR
            component_repo_name="${COMPONENT_REPO_PREFIX}-${component_name}"
            if wait_for_pac_and_merge_pr "${component_name}" "${component_repo_name}"; then
                log_info "   ✓ PAC PR merged - waiting for push event to trigger build..."
                
                # Step 5: Smart fallback - wait for push event to trigger build
                # If no build starts within 30s, manually trigger with annotation
                build_started=false
                for build_check_iter in {1..10}; do  # Wait up to 30s (10 * 3s)
                    if kubectl get pipelinerun -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -q "^${component_name}-on-push"; then
                        log_info "   ✓ Build started from push event (${build_check_iter}*3s)"
                        build_started=true
                        break
                    fi
                    sleep 3
                done
                
                if [ "$build_started" = "false" ]; then
                    log_warning "   ⚠️  No build from push event after 30s - triggering manually..."
                    kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                        "build.appstudio.openshift.io/request=trigger-pac-build" --overwrite &>/dev/null || \
                        log_warning "   ⚠️  Failed to annotate component"
                    log_info "   ✓ Manual build trigger sent"
                fi
            else
                log_warning "   ⚠️  PAC not configured, no build will trigger"
            fi
            
            echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
            echo "${component_name}:${app_name}" >> "${COMPONENTS_TO_BUILD}"  # Track for build monitoring
        fi
        
        # Delay to allow Quay.io repository auto-creation before build starts
        # Allows GitHub to propagate branch and avoid immediate conflicts
        # Spreads out API calls to reduce rate limit risk
        sleep 30
        
        # Batch delay: pause after every BATCH_SIZE components (10 min to allow multi-arch builds to complete)
        if [ $((actual_new_count % BATCH_SIZE)) -eq 0 ] && [ $actual_new_count -gt 0 ]; then
            log_info "   ⏸️  Pair complete (${actual_new_count} new components created)"
            log_info "   ⏳ Waiting ${BATCH_DELAY}s (10 min) for builds to complete before next pair..."
            sleep ${BATCH_DELAY}
            
            # Refresh cached data after delay (builds may have completed)
            log_info "   🔄 Refreshing component data (builds may have completed during wait)..."
            ALL_COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
                -l test.appstudio.openshift.io/type=multi-version-build \
                -o json 2>/dev/null || echo '{"items":[]}')
            ALL_PIPELINERUNS_JSON=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                -l pipelines.appstudio.openshift.io/type=build \
                -o json 2>/dev/null || echo '{"items":[]}')
            
            # Recount valid components with fresh data
            EXISTING_WITH_BUILDS=0
            while read -r comp_name; do
                # Konflux uses .status.lastPromotedImage (NOT .status.containerImage)
                promoted_image=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
                    ".items[] | select(.metadata.name == \"${comp_name}\") | .status.lastPromotedImage // \"\"")
                
                # Check lastPromotedImage
                if [ -n "${promoted_image}" ] && [ "${promoted_image}" != "null" ] && [[ "${promoted_image}" == *"@sha256:"* ]]; then
                    EXISTING_WITH_BUILDS=$((EXISTING_WITH_BUILDS + 1))
                else
                    # Fallback: Check PipelineRuns (for builds not yet promoted)
                    plr_success=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${comp_name}" '
                        [
                            .items[]
                            | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                            | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
                            | .metadata.name
                        ][0] // ""')
                    
                    if [ -n "${plr_success}" ]; then
                        EXISTING_WITH_BUILDS=$((EXISTING_WITH_BUILDS + 1))
                    fi
                fi
            done < <(echo "${ALL_COMPONENTS_JSON}" | jq -r '.items[].metadata.name')
            
            log_info "   📊 Updated count: ${EXISTING_WITH_BUILDS} components with successful builds"
        fi
    done
    
    log_success "  ✓ Processed version ${version}"
    
    # Check if we've hit the target across all versions
    # IMPORTANT: Count only VALID components (WITH successful builds), not zombies!
    # EXISTING_WITH_BUILDS is refreshed periodically and includes newly completed builds
    # Do NOT count created_count - those might be zombies or in-progress builds
    VALID_COMPONENTS_COUNT=$((EXISTING_WITH_BUILDS + quay_reused_count))
    if [ ${VALID_COMPONENTS_COUNT} -ge ${MAX_TOTAL_COMPONENTS} ]; then
        log_info "   ✅ Reached target of ${MAX_TOTAL_COMPONENTS} valid components (current: ${VALID_COMPONENTS_COUNT})"
        break
    fi
    
done < "${TEMP_DIR}/applications.txt"

echo "" >&2
if [ ${skipped_count} -gt 0 ]; then
    log_success "Created ${created_count} new components across ${PRODUCT_VERSIONS} product versions"
    build_reused=$((skipped_count - quay_reused_count - cannot_verify_count))
    log_info "   ♻️  Reused ${skipped_count} existing components:"
    if [ ${build_reused} -gt 0 ]; then
        log_info "      • ${build_reused} with successful builds"
    fi
    if [ ${quay_reused_count} -gt 0 ]; then
        log_info "      • ${quay_reused_count} discovered on Quay.io (no rebuild needed!)"
    fi
    if [ ${cannot_verify_count} -gt 0 ]; then
        log_info "      • ${cannot_verify_count} could not verify (kept to avoid false deletion)"
    fi
    log_info "   📊 Total: ${total_components} components (${created_count} new + ${skipped_count} reused)"
else
    log_success "Created ${created_count} total components across ${PRODUCT_VERSIONS} product versions"
fi

# Track actual created count separately from target
# Don't overwrite COMPONENT_COUNT - downstream validation needs the original target
ACTUAL_CREATED_COUNT=${total_components}

# ============================================================================
# Step 3: Wait for Builds to Start (or Create Manual PipelineRuns)
# ============================================================================

# Note: Step 3 removed - builds are triggered immediately via trigger-pac-build annotation
# No need to wait for PAC - annotation triggers builds instantly

# ============================================================================
# Step 4: Monitor Build Progress
# ============================================================================

# Skip monitoring if all components were reused
if [ ${created_count} -eq 0 ]; then
    log_section "♻️  Step 4/5: Verifying Reused Components"
    log_info "No new builds to monitor - verifying existing components have extractable digests..."
    echo "" >&2
    
    # Verify that reused components actually have extractable digests
    COMPLETED=0
    FAILED=0
    while IFS=: read -r component_name app_name; do
        [ -z "$component_name" ] && continue
        
        # Check if component has extractable digest
        image_ref=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.lastPromotedImage}' 2>/dev/null || echo "")
        
        if [ -z "$image_ref" ] || [[ "$image_ref" != *"@sha256:"* ]]; then
            # Try PipelineRun as fallback - get IMAGE_URL and IMAGE_DIGEST separately
            plr_name=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                -l "appstudio.openshift.io/component=${component_name}" \
                -l "pipelines.appstudio.openshift.io/type=build" \
                --sort-by=.metadata.creationTimestamp \
                -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
            
            if [ -n "$plr_name" ]; then
                # Check if it succeeded
                plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                    -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)
                
                if [ "$plr_status" = "True" ]; then
                    image_url=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                        -o jsonpath='{.status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null)
                    image_digest=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                        -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}' 2>/dev/null)
                    
                    if [ -n "$image_url" ] && [ -n "$image_digest" ]; then
                        image_base="${image_url%:*}"
                        image_ref="${image_base}@${image_digest}"
                    fi
                fi
            fi
        fi
        
        if [ -n "$image_ref" ] && [[ "$image_ref" == *"@sha256:"* ]]; then
            COMPLETED=$((COMPLETED + 1))
        else
            FAILED=$((FAILED + 1))
            log_warning "Component ${component_name} marked as reused but has no extractable digest"
        fi
    done < "${COMPONENT_LIST}"
    
    log_info "Verification complete:"
    log_info "   ✅ Valid digests: ${COMPLETED}"
    log_info "   ❌ Missing digests: ${FAILED}"
    echo "" >&2
    
    # If too many components are missing digests, fail early
    if [ ${FAILED} -gt $((total_components / 10)) ]; then
        log_error "Too many components (${FAILED}/${total_components}) are missing extractable digests"
        log_error "This indicates the components don't have successful builds"
        log_error "Try deleting failed components manually or running the test again"
        exit 1
    fi
else
    log_section "🔍 Step 4/5: Monitoring Build Progress"
    log_info "Build orchestration:"
    log_info "   New builds to monitor: ${created_count}"
    if [ ${skipped_count} -gt 0 ]; then
        log_info "   Reused builds (already successful): ${skipped_count}"
    fi
    log_info "   Max parallel builds: ${PARALLEL_BUILDS}"
    log_info "   Total timeout: ${BUILD_TIMEOUT}s ($((BUILD_TIMEOUT / 60)) minutes)"
    log_info "   Check interval: ${CHECK_INTERVAL}s"
    echo "" >&2
    
    # Verify COMPONENTS_TO_BUILD file exists and has content (only components needing builds, not Quay-discovered)
    if [ ! -f "${COMPONENTS_TO_BUILD}" ]; then
        log_error "COMPONENTS_TO_BUILD file not found: ${COMPONENTS_TO_BUILD}"
        exit 1
    fi
    
    components_to_build_count=$(wc -l < "${COMPONENTS_TO_BUILD}" || echo "0")
    if [ "${components_to_build_count}" -eq 0 ]; then
        log_info "   No components need builds (all discovered from Quay or reused) - skipping build monitoring"
    else
        log_info "   Monitoring ${components_to_build_count} components that need builds"
    fi

    # Skip monitoring if no components need builds
    if [ "${components_to_build_count}" -eq 0 ]; then
        log_info "   Skipping build monitoring (all components reused from Quay or existing builds)"
        COMPLETED=${skipped_count}
        FAILED=0
        ELAPSED_MIN=0
        ELAPSED_SEC=0
    else
        START_TIME=$(date +%s)
        COMPLETED=0
        FAILED=0

        while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        # Check build status for components that need builds (not Quay-discovered)
        COMPLETED=0
        FAILED=0
        RUNNING=0
        PENDING=0
        TOTAL_BUILDS=0
        COMPONENTS_CHECKED=0
        
        while IFS=: read -r component_name app_name; do
            [ -z "$component_name" ] && continue
            
            COMPONENTS_CHECKED=$((COMPONENTS_CHECKED + 1))
        
        # Get latest PipelineRun name first, then status (two-step for kubectl compatibility)
        plr_name=$(kubectl get pipelinerun -n "${NAMESPACE}" \
            -l "appstudio.openshift.io/component=${component_name}" \
            -l "pipelines.appstudio.openshift.io/type=build" \
            --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
        
        if [ -z "$plr_name" ]; then
            PENDING=$((PENDING + 1))
        else
            plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
            
            if [ -z "$plr_status" ]; then
                # PipelineRun exists but no status yet
                PENDING=$((PENDING + 1))
            else
                TOTAL_BUILDS=$((TOTAL_BUILDS + 1))
                case "$plr_status" in
                    "True")
                        COMPLETED=$((COMPLETED + 1))
                        ;;
                    "False")
                        FAILED=$((FAILED + 1))
                        ;;
                    "Unknown")
                        RUNNING=$((RUNNING + 1))
                        ;;
                    *)
                        PENDING=$((PENDING + 1))
                        ;;
                esac
            fi
        fi
    done < "${COMPONENTS_TO_BUILD}"
    
    # Debug: Check if we actually processed components
    if [ ${COMPONENTS_CHECKED} -eq 0 ]; then
        log_error "No components were checked! COMPONENTS_TO_BUILD might be unreadable"
        log_error "File: ${COMPONENTS_TO_BUILD}"
        log_error "Exists: $([ -f "${COMPONENTS_TO_BUILD}" ] && echo YES || echo NO)"
        log_error "Content sample: $(head -3 "${COMPONENTS_TO_BUILD}" 2>&1 || echo 'ERROR')"
        exit 1
    fi
    
    # Calculate progress percentage (based on components that need builds, not total count)
    TOTAL_DONE=$((COMPLETED + FAILED))
    PROGRESS_PCT=$((TOTAL_DONE * 100 / components_to_build_count))
    
    # Format time
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))
    
    # Progress bar
    BAR_WIDTH=40
    FILLED=$((PROGRESS_PCT * BAR_WIDTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')
    EMPTY=$(printf "%$((BAR_WIDTH - FILLED))s" | tr ' ' '░')
    
    echo -ne "\r   [${ELAPSED_MIN}m${ELAPSED_SEC}s] [${BAR}${EMPTY}] ${PROGRESS_PCT}% | ✅ ${COMPLETED} | 🔄 ${RUNNING} | ⏳ ${PENDING} | ❌ ${FAILED}  " >&2
    
    # Check timeout
    if [ $ELAPSED -gt $BUILD_TIMEOUT ]; then
        echo "" >&2
        log_error "Timeout: Builds did not complete within ${BUILD_TIMEOUT}s ($((BUILD_TIMEOUT / 60)) minutes)"
        log_info "   Completed: ${COMPLETED}/${components_to_build_count}"
        log_info "   Failed: ${FAILED}"
        log_info "   Still running/pending: $((components_to_build_count - TOTAL_DONE))"
        exit 1
    fi
    
    # Check if we're done (all builds completed or failed)
    if [ $TOTAL_DONE -ge $components_to_build_count ]; then
        echo "" >&2
        break
    fi
    
        sleep $CHECK_INTERVAL
    done

    echo "" >&2
    log_section "📊 Build Summary"
    log_info "   ✅ Succeeded: ${COMPLETED}"
    log_info "   ❌ Failed: ${FAILED}"
    log_info "   ⏱️  Total time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
    fi  # End of "if [ "${components_to_build_count}" -eq 0 ]" check
    
    # Collect failed components for potential retry
    FAILED_COMPONENTS_FILE="${TEMP_DIR}/failed-components.txt"
    > "${FAILED_COMPONENTS_FILE}"  # Clear file
    
    if [ ${FAILED} -gt 0 ] || [ ${PENDING} -gt 0 ]; then
        log_info ""
        log_info "🧹 Collecting components without successful builds..."
        DELETED_FAILED=0
        DELETED_STUCK=0
        while IFS=: read -r component_name app_name; do
            [ -z "$component_name" ] && continue
            
            # Check if this component has a build and its status
            plr_name=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                -l "appstudio.openshift.io/component=${component_name}" \
                -l "pipelines.appstudio.openshift.io/type=build" \
                --sort-by=.metadata.creationTimestamp \
                -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
            
            if [ -z "$plr_name" ]; then
                # No build at all - stuck in PAC configuration
                log_info "   Deleting component (no build): ${component_name}"
                echo "${component_name}:${app_name}" >> "${FAILED_COMPONENTS_FILE}"
                force_delete_component "${component_name}" "${NAMESPACE}"
                DELETED_STUCK=$((DELETED_STUCK + 1))
            else
                plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                    -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
                
                if [ "$plr_status" = "False" ]; then
                    # Build failed
                    log_info "   Deleting component (build failed): ${component_name}"
                    echo "${component_name}:${app_name}" >> "${FAILED_COMPONENTS_FILE}"
                    force_delete_component "${component_name}" "${NAMESPACE}"
                    DELETED_FAILED=$((DELETED_FAILED + 1))
                fi
            fi
        done < "${COMPONENTS_TO_BUILD}"
        log_info "   Deleted ${DELETED_FAILED} failed + ${DELETED_STUCK} stuck components"
        
        # Auto-retry if failures are reasonable (likely transient issues like platform resource exhaustion)
        TOTAL_DELETED=$((DELETED_FAILED + DELETED_STUCK))
        MAX_RETRY_THRESHOLD=50  # Retry up to 50 failures (transient issues like ppc64le/s390x quota)
        
        if [ ${TOTAL_DELETED} -gt 0 ] && [ ${TOTAL_DELETED} -le ${MAX_RETRY_THRESHOLD} ]; then
            log_info ""
            log_info "🔄 Auto-retry: ${TOTAL_DELETED} failures detected (≤${MAX_RETRY_THRESHOLD} threshold)"
            log_info "   Likely transient errors (e.g., platform quota exhaustion) - retrying with batching..."
            log_info "   Batch strategy: ${BATCH_SIZE} components per pair, ${BATCH_DELAY}s (10 min) delays"
            sleep 5  # Brief pause for cleanup to propagate
            
            # Recreate failed components using SAME batching as main build (pairs with 10-min delays)
            RETRY_COUNT=0
            RETRY_ACTUAL_NEW=0
            while IFS=: read -r component_name app_name; do
                [ -z "$component_name" ] && continue
                
                log_info "   🔄 Recreating: ${component_name}"
                
                # Define component-specific branch
                component_branch="${COMPONENT_BRANCH_PREFIX}-${component_name}"
                
                # Component creation with configure-pac (no build trigger yet)
                # This avoids race condition where PAC fires before component exists
                kubectl create -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Component
metadata:
  name: ${component_name}
  namespace: ${NAMESPACE}
  labels:
    appstudio.application: ${app_name}
    test.appstudio.openshift.io/type: "multi-version-build"
  annotations:
    build.appstudio.openshift.io/request: "configure-pac"
    image.redhat.com/generate: "{\"visibility\": \"public\"}"
    image-controller.appstudio.redhat.com/skip-repository-deletion: "true"
    test.appstudio.openshift.io/fresh-build: "true"
    build.appstudio.openshift.io/pipeline: >-
      {"name": "docker-build-multi-platform-oci-ta",
      "bundle": "quay.io/konflux-ci/tekton-catalog/pipeline-docker-build-multi-platform-oci-ta:devel"}
    test.appstudio.openshift.io/retry-attempt: "1"
    test.appstudio.openshift.io/pac-branch: "${component_branch}"
    build.appstudio.openshift.io/multi-platform-required: "true"
    build.appstudio.openshift.io/request-platforms: "linux/amd64,linux/arm64,linux/s390x,linux/ppc64le"
spec:
  application: ${app_name}
  componentName: ${component_name}
  secret: pipelines-as-code-secret
  containerImage: ""
  source:
    git:
      context: ./
      dockerfileUrl: Dockerfile
      revision: ${component_branch}
      url: https://github.com/${COMPONENT_REPO_ORG}/${COMPONENT_REPO_PREFIX}-${component_name}
EOF
                # Wait for PAC to create the service account
                service_account_name="build-pipeline-${component_name}"
                wait_time=0
                max_wait=60
                while [ $wait_time -lt $max_wait ]; do
                    if kubectl get serviceaccount "${service_account_name}" -n "${NAMESPACE}" &>/dev/null; then
                        break
                    fi
                    sleep 2
                    wait_time=$((wait_time + 2))
                done
                
                # Trigger PAC build with annotation (after git push already happened)
                kubectl annotate component "${component_name}" -n "${NAMESPACE}" \
                    "build.appstudio.openshift.io/request=trigger-pac-build" --overwrite &>/dev/null || true
                
                RETRY_COUNT=$((RETRY_COUNT + 1))
                RETRY_ACTUAL_NEW=$((RETRY_ACTUAL_NEW + 1))
                
                # Batch delay: pause after every BATCH_SIZE components (10 min to allow multi-arch builds to complete)
                if [ $((RETRY_ACTUAL_NEW % BATCH_SIZE)) -eq 0 ] && [ $RETRY_ACTUAL_NEW -gt 0 ]; then
                    log_info "   ⏸️  Retry pair complete (${RETRY_ACTUAL_NEW} components retried)"
                    log_info "   ⏳ Waiting ${BATCH_DELAY}s (10 min) for retry builds to complete before next pair..."
                    sleep ${BATCH_DELAY}
                    
                    # Refresh status after delay
                    log_info "   🔄 Checking retry build progress..."
                    retry_progress_completed=0
                    retry_progress_running=0
                    while IFS=: read -r check_component_name check_app_name; do
                        [ -z "$check_component_name" ] && continue
                        plr_check=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                            -l "appstudio.openshift.io/component=${check_component_name}" \
                            -l "pipelines.appstudio.openshift.io/type=build" \
                            --sort-by=.metadata.creationTimestamp \
                            -o jsonpath='{.items[-1].status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
                        [ "$plr_check" = "True" ] && retry_progress_completed=$((retry_progress_completed + 1))
                        [ "$plr_check" = "Unknown" ] && retry_progress_running=$((retry_progress_running + 1))
                    done < "${FAILED_COMPONENTS_FILE}"
                    log_info "   📊 Progress: ✅ ${retry_progress_completed} completed, 🔄 ${retry_progress_running} running"
                fi
            done < "${FAILED_COMPONENTS_FILE}"
            
            log_info "   Created ${RETRY_COUNT} retry components (batched with ${BATCH_DELAY}s (10 min) delays)"
            log_info ""
            log_info "🔍 Monitoring retry builds (timeout: 30 minutes)..."
            
            # Monitor retry builds
            RETRY_START_TIME=$(date +%s)
            RETRY_TIMEOUT=1800  # 30 minutes for retry
            RETRY_COMPLETED=0
            RETRY_FAILED=0
            
            while true; do
                CURRENT_TIME=$(date +%s)
                RETRY_ELAPSED=$((CURRENT_TIME - RETRY_START_TIME))
                
                RETRY_COMPLETED=0
                RETRY_FAILED=0
                RETRY_RUNNING=0
                RETRY_PENDING=0
                
                while IFS=: read -r component_name app_name; do
                    [ -z "$component_name" ] && continue
                    
                    plr_name=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                        -l "appstudio.openshift.io/component=${component_name}" \
                        -l "pipelines.appstudio.openshift.io/type=build" \
                        --sort-by=.metadata.creationTimestamp \
                        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
                    
                    if [ -z "$plr_name" ]; then
                        RETRY_PENDING=$((RETRY_PENDING + 1))
                    else
                        plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${NAMESPACE}" \
                            -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
                        
                        case "$plr_status" in
                            "True") RETRY_COMPLETED=$((RETRY_COMPLETED + 1)) ;;
                            "False") RETRY_FAILED=$((RETRY_FAILED + 1)) ;;
                            "Unknown") RETRY_RUNNING=$((RETRY_RUNNING + 1)) ;;
                            *) RETRY_PENDING=$((RETRY_PENDING + 1)) ;;
                        esac
                    fi
                done < "${FAILED_COMPONENTS_FILE}"
                
                RETRY_TOTAL_DONE=$((RETRY_COMPLETED + RETRY_FAILED))
                RETRY_ELAPSED_MIN=$((RETRY_ELAPSED / 60))
                RETRY_ELAPSED_SEC=$((RETRY_ELAPSED % 60))
                
                echo -ne "\r   [${RETRY_ELAPSED_MIN}m${RETRY_ELAPSED_SEC}s] Retry: ✅ ${RETRY_COMPLETED} | 🔄 ${RETRY_RUNNING} | ⏳ ${RETRY_PENDING} | ❌ ${RETRY_FAILED}  " >&2
                
                # Check if done
                if [ ${RETRY_TOTAL_DONE} -eq ${RETRY_COUNT} ]; then
                    echo "" >&2
                    break
                fi
                
                # Check timeout
                if [ ${RETRY_ELAPSED} -gt ${RETRY_TIMEOUT} ]; then
                    echo "" >&2
                    log_warning "Retry timeout reached (${RETRY_TIMEOUT}s)"
                    break
                fi
                
                sleep ${CHECK_INTERVAL}
            done
            
            log_info ""
            log_info "🔄 Retry Results:"
            log_info "   ✅ Succeeded: ${RETRY_COMPLETED}"
            log_info "   ❌ Still failed: ${RETRY_FAILED}"
            
            # Update overall counts
            COMPLETED=$((COMPLETED + RETRY_COMPLETED))
            FAILED=${RETRY_FAILED}
            
            log_info ""
            log_info "📊 Final Build Summary (including retries):"
            log_info "   ✅ Total succeeded: ${COMPLETED}"
            log_info "   ❌ Total failed: ${FAILED}"
            
        elif [ ${TOTAL_DELETED} -gt ${MAX_RETRY_THRESHOLD} ]; then
            log_warning ""
            log_warning "Too many failures (${TOTAL_DELETED} > ${MAX_RETRY_THRESHOLD}) - skipping auto-retry"
            log_warning "This indicates a systemic issue rather than transient platform resource exhaustion"
            log_warning "Manual investigation recommended"
            log_warning "Likely a systematic issue, not transient errors"
        fi
    fi
fi

# Check if we have enough successful builds (compare against actual builds attempted, not total target)
MIN_SUCCESS=$((created_count * 90 / 100))  # 90% threshold of created components
if [ ${COMPLETED} -lt ${MIN_SUCCESS} ]; then
    log_warning "Low success rate: ${COMPLETED}/${created_count} (expected at least ${MIN_SUCCESS})"
    log_info "This is common due to GitHub/Quay.io rate limiting on first runs"
    log_info "Failed components will be cleaned up on next run or by validation"
    log_info ""
    log_info "Review all builds for this test:"
    log_info "   kubectl get pipelinerun -n ${NAMESPACE} -l pipelines.appstudio.openshift.io/type=build | grep -E '(v4-[0-9]+-|large-snapshot)'"
    # Don't fail - just proceed with successful builds
    # Validation script will clean up components without images
fi

fi  # End of "if [ ${SKIP_CREATION} = false ]" (skip creation when at max)

# Set MIN_SUCCESS for final validation (needed for both creation and reuse paths)
if [ "${SKIP_CREATION}" = "true" ]; then
    # When reusing, expect 90% of existing valid components to have extractable images
    MIN_SUCCESS=$((EXISTING_WITH_BUILDS * 90 / 100))
else
    # MIN_SUCCESS already set in creation block above (line 1681)
    : # No-op, MIN_SUCCESS was set at line 1681
fi

# ============================================================================
# Step 5: Extract Image Digests
# ============================================================================

log_section "📋 Step 5/5: Extracting Image Digests"
log_info "Collecting container image references from successful builds..."
log_info "Using cached component and PipelineRun data for efficiency..."
echo "" >&2

# Wait for Quay registry replication to complete
# PipelineRun "Succeeded" means push finished, but Quay replication may still be in progress
log_info "⏳ Waiting 90s for Quay registry replication to complete..."
log_info "   (Images may still be propagating after PipelineRun success)"
sleep 90
echo "" >&2

SUCCESS_COUNT=0
SIGNED_COUNT=0
> "${OUTPUT_FILE}"

# Create a temporary file to track per-version statistics
> "${TEMP_DIR}/version-stats.txt"

# Refresh the cached data if we just created new components
if [ "${SKIP_CREATION}" = "false" ]; then
    log_info "Refreshing component data after creation..."
    ALL_COMPONENTS_JSON=$(kubectl get components -n "${NAMESPACE}" \
        -l test.appstudio.openshift.io/type=multi-version-build \
        -o json 2>/dev/null || echo '{"items":[]}')
    ALL_PIPELINERUNS_JSON=$(kubectl get pipelinerun -n "${NAMESPACE}" \
        -l pipelines.appstudio.openshift.io/type=build \
        -o json 2>/dev/null || echo '{"items":[]}')
fi

component_list_size=$(wc -l < "${COMPONENT_LIST}" || echo "0")
log_info "Processing ${component_list_size} components..."
PROGRESS_INTERVAL=25

while IFS=: read -r component_name app_name; do
    [ -z "$component_name" ] && continue
    
    # Try 1: Get container image from cached component data (status.lastPromotedImage)
    image_ref=$(echo "${ALL_COMPONENTS_JSON}" | jq -r \
        ".items[] | select(.metadata.name == \"${component_name}\") | .status.lastPromotedImage // \"\"")
    
    # Try 2: If lastPromotedImage is empty, get from PipelineRun results
    if [ -z "$image_ref" ] || [ "$image_ref" = "null" ] || [[ "$image_ref" != *"@sha256:"* ]]; then
        # Get latest successful PipelineRun from cached data
        plr_data=$(echo "${ALL_PIPELINERUNS_JSON}" | jq -r --arg comp "${component_name}" '
            [
                .items[]
                | select(.metadata.labels["appstudio.openshift.io/component"] == $comp)
                | select(.status.conditions[]? | select(.type == "Succeeded" and .status == "True"))
                | {
                    url: (.status.results[]? | select(.name == "IMAGE_URL") | .value),
                    digest: (.status.results[]? | select(.name == "IMAGE_DIGEST") | .value)
                  }
                | select(.url and .digest)
                | "\(.url)|\(.digest)"
            ][0] // ""')
        
        if [ -n "$plr_data" ] && [ "$plr_data" != "null" ]; then
            image_url="${plr_data%|*}"
            image_digest="${plr_data#*|}"
            if [ -n "$image_url" ] && [ -n "$image_digest" ]; then
                image_base="${image_url%:*}"
                image_ref="${image_base}@${image_digest}"
            fi
        fi
    fi
    
    # Validate image reference format
    if [ -n "$image_ref" ] && [ "$image_ref" != "null" ] && [[ "$image_ref" == *"@sha256:"* ]]; then
        # First, verify this is a REAL container image, not an attestation artifact
        image_is_valid=""
        if command -v skopeo &>/dev/null; then
            image_config=$(skopeo inspect --raw --config "docker://${image_ref}" 2>/dev/null || echo "{}")
            image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
            
            if [ -n "$image_arch" ] && [ "$image_arch" != "null" ]; then
                image_is_valid="true"
            else
                log_info "   ⚠️  Skipping attestation artifact for ${component_name}"
            fi
        else
            # No skopeo - assume valid
            image_is_valid="true"
        fi
        
        if [ "$image_is_valid" = "true" ]; then
            # Verify this image has Tekton Chains signatures on Quay.io
            # Extract digest from image_ref
            digest="${image_ref##*@}"
            sig_tag="sha256-${digest##*:}.sig"
            
            # Check if .sig tag exists on Quay.io (indicates Tekton Chains signed it)
            repo_url="https://quay.io/api/v1/repository/redhat-user-workloads-stage/${NAMESPACE}/${component_name}"
            sig_check=$(curl -s "${repo_url}/tag/${sig_tag}" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || echo "")
            
            if [ -n "$sig_check" ]; then
            # Image has Chains signature
            echo "${image_ref}" >> "${OUTPUT_FILE}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            SIGNED_COUNT=$((SIGNED_COUNT + 1))
        else
            # Image exists but no Chains signature - check for newer signed image
            log_warning "   ⚠️  ${component_name} image lacks Chains signature, checking for newer build..."
            
            # Query Quay for tags with signatures
            tags_url="${repo_url}/tag/?onlyActiveTags=true&limit=50"
            tags_response=$(curl -s "${tags_url}" 2>/dev/null)
            
            # Find most recent image with .sig tag
            signed_digest=""
            while IFS= read -r tag_name; do
                [ -z "$tag_name" ] && continue
                tag_digest=$(echo "$tags_response" | jq -r --arg tag "$tag_name" \
                    '[.tags[] | select(.name == $tag) | .manifest_digest][0] // ""')
                sig_tag_check="sha256-${tag_digest##*:}.sig"
                has_sig=$(echo "$tags_response" | jq -r --arg sig "$sig_tag_check" \
                    '.tags[] | select(.name == $sig) | .name' 2>/dev/null)
                
                if [ -n "$has_sig" ]; then
                    # Verify this is a REAL container image, not an attestation artifact
                    test_image="quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}@${tag_digest}"
                    if command -v skopeo &>/dev/null; then
                        image_config=$(skopeo inspect --raw --config "docker://${test_image}" 2>/dev/null || echo "{}")
                        image_arch=$(echo "$image_config" | jq -r '.architecture // ""' 2>/dev/null || echo "")
                        
                        if [ -n "$image_arch" ] && [ "$image_arch" != "null" ]; then
                            # Valid container image with architecture
                            signed_digest="$tag_digest"
                            break
                        else
                            log_info "      Skipping attestation artifact (no arch): ${tag_name}"
                        fi
                    else
                        # No skopeo - assume valid
                        signed_digest="$tag_digest"
                        break
                    fi
                fi
            done < <(echo "$tags_response" | jq -r '.tags[] | select(.name | (contains(".sig") or contains(".att") or contains(".sbom") or contains(".dockerfile") or contains(".git")) | not) | .name')
            
            if [ -n "$signed_digest" ]; then
                # Found newer image with signature! Update component and use it
                signed_image="quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}@${signed_digest}"
                log_info "   ✓ Found signed image with valid architecture, updating component: ${component_name}"
                
                kubectl patch component "${component_name}" -n "${NAMESPACE}" --type=merge -p "{
                  \"spec\": {
                    \"containerImage\": \"${signed_image}\"
                  }
                }" &>/dev/null || true
                
                echo "${signed_image}" >> "${OUTPUT_FILE}"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                SIGNED_COUNT=$((SIGNED_COUNT + 1))
            else
                log_warning "   ⚠️  No signed images found for ${component_name}, skipping"
            fi
        fi
        fi
        
        # Track per-version stats
        version=$(echo "$app_name" | grep -oP 'v\K[0-9.]+' || echo "unknown")
        echo "${version}" >> "${TEMP_DIR}/version-stats.txt"
        
        # Progress logging
        if (( SUCCESS_COUNT % PROGRESS_INTERVAL == 0 )); then
            log_info "   Extracted ${SUCCESS_COUNT} digests..."
        fi
    fi
done < "${COMPONENT_LIST}"

echo "" >&2
log_section "✅ Build Complete - Fresh Images Ready"
log_success "Successfully extracted ${SUCCESS_COUNT} fresh image digests"
log_info "   Multi-version: ${PRODUCT_VERSIONS} versions × ~$((COMPONENT_COUNT / PRODUCT_VERSIONS)) components"
log_info "   Output file: ${OUTPUT_FILE}"
log_info "   Namespace: ${NAMESPACE}"
echo "" >&2

log_info "📊 Distribution by product version:"
sort "${TEMP_DIR}/version-stats.txt" | uniq -c | while read -r count version; do
    log_info "   Version ${version}: ${count} images"
done
echo "" >&2

log_info "🔐 Tekton Chains Signature Status:"
log_info "   Images with signatures: ${SIGNED_COUNT}/${SUCCESS_COUNT}"
if [ ${SIGNED_COUNT} -eq 0 ]; then
    log_warning "   ⚠️  No Tekton Chains signatures found!"
    log_warning "   This may indicate:"
    log_warning "     • Builds completed before Tekton Chains processed them"
    log_warning "     • Chains is not properly configured in this namespace"
    log_warning "     • Images were built without PAC workflow"
elif [ ${SIGNED_COUNT} -lt ${SUCCESS_COUNT} ]; then
    log_warning "   ⚠️  Only ${SIGNED_COUNT}/${SUCCESS_COUNT} images have signatures"
    log_info "   Some builds may still be processing, or signatures failed to generate"
else
    log_success "   ✓ All images have Tekton Chains attestations and signatures"
fi
echo "" >&2

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 6: Patch Component Specs with Quay Digests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Konflux doesn't auto-update component.spec.containerImage with build digests
# This step ensures all components have the correct @sha256:... references
# from Quay.io, which is the source of truth for built images

log_section "📋 Step 6/6: Patching Component Digests from Quay"
log_info "Updating component specs with actual image digests from Quay.io registry..."
echo "" >&2

PATCHED_COUNT=0
ALREADY_CORRECT=0
PATCH_FAILED=0

# Process all components created by this script
# Format: component_name:app_name (matches how we write to COMPONENT_LIST)
while IFS=: read -r component_name app_name; do
    [ -z "$component_name" ] && continue
    [ -z "$app_name" ] && continue
    
    # Check if this component was actually rebuilt (has PipelineRuns from this run)
    # Components that were reused (not rebuilt) don't need patching - they already have valid digests
    plr_count=$(kubectl get pipelinerun -n "${NAMESPACE}" \
        -l "appstudio.openshift.io/component=${component_name}" \
        -l "pipelines.appstudio.openshift.io/type=build" \
        --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$plr_count" -eq 0 ]; then
        # Component wasn't rebuilt - skip patching (already has valid digest from previous run)
        log_info "   ⏭️  ${component_name}: Skipped (reused from previous run)"
        ALREADY_CORRECT=$((ALREADY_CORRECT + 1))
        continue
    fi
    
    base="quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}"
    
    # Get sha256-* tag from Quay (excluding .sig, .att, .sbom, .dockerfile)
    digest_tag=$(skopeo list-tags docker://${base} 2>/dev/null | \
        jq -r '[.Tags[] | select(startswith("sha256-") and
        ((endswith(".att") or endswith(".sig") or
         endswith(".sbom") or endswith(".dockerfile")) | not))][0] // ""' 2>/dev/null)
    
    if [ -n "$digest_tag" ]; then
        digest="sha256:${digest_tag#sha256-}"
        
        # Check if component already has this digest
        current_image=$(kubectl get component ${component_name} -n ${NAMESPACE} \
            -o jsonpath='{.spec.containerImage}' 2>/dev/null || echo "")
        
        if [[ "$current_image" == *"@${digest}" ]]; then
            log_info "   ✅ ${component_name}: Already has correct digest"
            ALREADY_CORRECT=$((ALREADY_CORRECT + 1))
        else
            log_info "   🔧 ${component_name}: Patching with ${digest:0:19}..."
            if kubectl patch component ${component_name} -n ${NAMESPACE} \
                --type=merge \
                -p "{\"spec\":{\"containerImage\":\"${base}@${digest}\"}}" &>/dev/null; then
                PATCHED_COUNT=$((PATCHED_COUNT + 1))
            else
                log_warning "   ⚠️  ${component_name}: Patch failed"
                PATCH_FAILED=$((PATCH_FAILED + 1))
            fi
        fi
    else
        log_warning "   ⚠️  ${component_name}: No digest found on Quay"
        PATCH_FAILED=$((PATCH_FAILED + 1))
    fi
done < "${COMPONENT_LIST}"

echo "" >&2
log_success "Component patching complete:"
log_info "   Patched: ${PATCHED_COUNT}"
log_info "   Already correct: ${ALREADY_CORRECT}"
if [ ${PATCH_FAILED} -gt 0 ]; then
    log_warning "   Failed: ${PATCH_FAILED}"
fi
echo "" >&2

log_info "🔍 Extracted images:"
if [ ${SUCCESS_COUNT} -le 10 ]; then
    # Show all if 10 or fewer
    while read -r img; do
        echo "   ${img}" >&2
    done < "${OUTPUT_FILE}"
else
    # Show first 5 and last 3 for larger sets
    log_info "   First 5:"
    head -5 "${OUTPUT_FILE}" | while read -r img; do
        echo "     ${img}" >&2
    done
    echo "     ... ($((SUCCESS_COUNT - 8)) more images) ..." >&2
    log_info "   Last 3:"
    tail -3 "${OUTPUT_FILE}" | while read -r img; do
        echo "     ${img}" >&2
    done
fi
echo "" >&2

log_info "⚠️  IMPORTANT: These images are fresh builds with ZERO Red Hat signatures"
log_info "   Expected signing performance:"
log_info "     • Multi-Architecture: 4 architectures (amd64, arm64, s390x, ppc64le)"
log_info "     • Total digests to sign: ~$((SUCCESS_COUNT * 4)) (${SUCCESS_COUNT} images × 4 architectures)"
log_info "     • Signing time: 6-8 hours (NO idempotency benefits)"
log_info "     • This simulates MAXIMUM worst-case production release signing at scale"
echo "" >&2

log_info "🧹 Cleanup (optional):"
log_info "   # Delete all product version applications after testing:"
if [ -f "${TEMP_DIR}/applications.txt" ]; then
    while IFS=: read -r app_name _; do
        [ -z "$app_name" ] && continue
        log_info "   kubectl delete application ${app_name} -n ${NAMESPACE}"
    done < "${TEMP_DIR}/applications.txt"
else
    # Applications weren't created this run (SKIP_CREATION mode)
    log_info "   kubectl delete application -l test.appstudio.openshift.io/type=multi-version-build -n ${NAMESPACE}"
fi
echo "" >&2

# Final validation
if [ ${SUCCESS_COUNT} -lt ${MIN_SUCCESS} ]; then
    log_error "Could not extract enough image digests: ${SUCCESS_COUNT}/${COMPLETED}"
    exit 1
fi

log_success "Fresh build process completed successfully!"
log_info "   Ready for worst-case signing test with ${SUCCESS_COUNT} unsigned images"

exit 0
