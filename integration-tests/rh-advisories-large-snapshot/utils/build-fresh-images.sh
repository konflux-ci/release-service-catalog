#!/bin/bash
set -euo pipefail

# ============================================================================
# build-fresh-images.sh - Build fresh Konflux components for worst-case testing
# ============================================================================
#
# PURPOSE:
#   Build 200 fresh Konflux components with ZERO existing Red Hat signatures
#   to test true worst-case signing performance (Strategy C).
#
# STRATEGY:
#   - Create temporary Application in Konflux
#   - Create 200 Components using known-good base repository
#   - Trigger builds with unique identifiers to ensure fresh builds
#   - Wait for builds to complete in parallel
#   - Extract container image digests from successful builds
#   - Output image pool file for use in large snapshot test
#
# USAGE:
#   ./build-fresh-images.sh [component_count] [namespace] [output_file]
#
#   IMPORTANT: First run takes 3-4 hours due to GitHub API rate limiting.
#              Subsequent runs complete in 2-3 minutes by reusing existing builds!
#
# ARGUMENTS:
#   component_count : Number of components to build (default: 200)
#   namespace       : Kubernetes namespace for builds (default: dev-release-team-tenant)
#   output_file     : Output file for image pool (default: /tmp/fresh-images-pool-TIMESTAMP.txt)
#
# ENVIRONMENT:
#   PARALLEL_BUILDS   : Max parallel builds (default: 50)
#   BUILD_TIMEOUT     : Total timeout in seconds (default: 21600 = 6 hours)
#                       Must account for batching delays + build time
#   CHECK_INTERVAL    : Status check interval in seconds (default: 30)
#   BATCH_SIZE        : Components per batch (default: 20) - controls API rate limit load
#   BATCH_DELAY       : Delay between batches in seconds (default: 900 = 15 min)
#                       Only applies when creating NEW components (not reused ones)
#   FORCE_REBUILD     : Force rebuild even if images exist (default: false)
#   BASE_REPO         : GitHub repository for component source (default: hacbs-release-tests/e2e-base)
#   BASE_BRANCH       : Branch to use from base repo (default: push-to-external-registry-base)
#
# OUTPUT:
#   Creates a file with one container image reference per line:
#     quay.io/redhat-user-workloads/namespace/app/component@sha256:abc123...
#     quay.io/redhat-user-workloads/namespace/app/component@sha256:def456...
#
# PERFORMANCE:
#   First run (building 200 components):
#     - Component creation: ~2.5-3 hours (batched in groups of 20 with 15-min delays)
#     - Build execution: ~30-40 minutes (50 concurrent builds)
#     - Total: ~3-4 hours
#   
#   Subsequent runs (reusing existing components):
#     - Component verification: ~30 seconds
#     - No builds needed: ~0 minutes
#     - Total: ~2-3 minutes (reuses all successful builds!)
#   
#   Notes:
#     - Batching prevents GitHub API rate limit exhaustion
#     - Reused components don't trigger delays
#     - Progress updates every 30 seconds during monitoring
#
# CLEANUP:
#   Application and components are intentionally LEFT in namespace for debugging.
#   To clean up manually:
#     kubectl delete application <app-name> -n <namespace>
#
# EXAMPLES:
#   # Build 200 components (default)
#   ./build-fresh-images.sh
#
#   # Build 100 components in custom namespace
#   ./build-fresh-images.sh 100 my-tenant-namespace
#
#   # Custom parallel builds and faster checks
#   PARALLEL_BUILDS=100 CHECK_INTERVAL=15 ./build-fresh-images.sh
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Configuration
# ============================================================================

# Command-line arguments
COMPONENT_COUNT="${1:-200}"
NAMESPACE="${2:-dev-release-team-tenant}"
OUTPUT_FILE="${3:-/tmp/fresh-images-pool-$(date +%s).txt}"

# Multi-version simulation settings - realistic production scenario
# Multiple product versions each with multiple components
PRODUCT_VERSIONS="${PRODUCT_VERSIONS:-8}"              # Number of product versions
COMPONENTS_PER_VERSION="${COMPONENTS_PER_VERSION:-25}"  # Components per version (~25 each)
VERSION_VARIANCE="${VERSION_VARIANCE:-3}"      # +/- variance in component count per version

# Application naming - one app per product version
# Instead of one large app, create multiple apps representing different versions
# Use stable naming (no timestamp) to enable image reuse across test runs
APP_PREFIX="large-snapshot-build"

# Base repository (known-good repo with working Dockerfile)
BASE_REPO="${BASE_REPO:-hacbs-release-tests/e2e-base}"
BASE_BRANCH="${BASE_BRANCH:-push-to-external-registry-base}"
BASE_GITHUB_URL="https://github.com/${BASE_REPO}"

# Build orchestration settings
PARALLEL_BUILDS="${PARALLEL_BUILDS:-50}"      # Max concurrent builds
BUILD_TIMEOUT="${BUILD_TIMEOUT:-21600}"       # 6 hours total (accounts for batching + builds)
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"        # Status check every 30s
BATCH_SIZE="${BATCH_SIZE:-20}"                # Create components in batches (avoid quota/rate limits)
BATCH_DELAY="${BATCH_DELAY:-900}"             # Wait 15 minutes between batches (GitHub API rate limit)
FORCE_REBUILD="${FORCE_REBUILD:-false}"       # Force rebuild even if images exist

# Retry settings
MAX_RETRIES=3
RETRY_DELAY=5

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
)

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
    local container_image
    container_image=$(kubectl get component "${component_name}" -n "${namespace}" \
        -o jsonpath='{.status.containerImage}' 2>/dev/null || echo "")
    
    # If status has valid digest, component is ready to reuse
    if [ -n "${container_image}" ] && [[ "${container_image}" == *"@sha256:"* ]]; then
        return 0
    fi
    
    # Fallback: Check if there's a successful PipelineRun with IMAGE_URL result
    local image_url
    image_url=$(kubectl get pipelinerun -n "${namespace}" \
        -l "appstudio.openshift.io/component=${component_name}" \
        -l "pipelines.appstudio.openshift.io/type=build" \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Succeeded" && @.status=="True")])].status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null | tail -1 || echo "")
    
    if [ -n "${image_url}" ] && [[ "${image_url}" == *"@sha256:"* ]]; then
        return 0
    fi
    
    # No usable build found
    return 1
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
COMPONENT_LIST="${TEMP_DIR}/components.txt"

# ============================================================================
# Validate Prerequisites
# ============================================================================

log_section "🔍 Validating Prerequisites"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found in PATH"
    exit 1
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

log_success "Prerequisites validated"
log_info "   Cluster: $(kubectl config current-context)"
log_info "   Namespace: ${NAMESPACE}"
log_info "   Total components: ${COMPONENT_COUNT}"
log_info "   Product versions: ${PRODUCT_VERSIONS}"
log_info "   Components/version: ~${COMPONENTS_PER_VERSION} (±${VERSION_VARIANCE})"
echo "" >&2
log_info "🎯 Multi-Version Strategy:"
log_info "   Building ${PRODUCT_VERSIONS} different product versions (e.g., 4.15, 4.16, etc.)"
log_info "   Each version has ~${COMPONENTS_PER_VERSION} components with realistic component names"
log_info "   This mirrors actual production release patterns for accurate testing"

# ============================================================================
# Step 1: Create Application
# ============================================================================

log_section "📦 Step 1/5: Creating Applications (Multi-Version)"
log_info "Creating ${PRODUCT_VERSIONS} product versions with ~${COMPONENTS_PER_VERSION} components each"
log_info "This mirrors real-world production release scenarios"
echo "" >&2

# Calculate actual distribution
TOTAL_COMPONENTS_TARGET="${COMPONENT_COUNT}"
COMPONENTS_PER_VERSION_BASE=$((TOTAL_COMPONENTS_TARGET / PRODUCT_VERSIONS))

# Create applications for each product version
for (( v=0; v<PRODUCT_VERSIONS; v++ )); do
    VERSION_PATTERN="${VERSION_PATTERNS[$v]}"
    # Replace dots with hyphens for Kubernetes naming compliance
    VERSION_SAFE="${VERSION_PATTERN//./-}"
    APP_NAME="${APP_PREFIX}-v${VERSION_SAFE}"
    
    # Add variance to component count for realism (+/- VERSION_VARIANCE)
    VARIANCE=$((RANDOM % (VERSION_VARIANCE * 2 + 1) - VERSION_VARIANCE))
    VERSION_COMPONENT_COUNT=$((COMPONENTS_PER_VERSION_BASE + VARIANCE))
    
    log_info "Ensuring Application exists: ${APP_NAME}"
    log_info "  Version: ${VERSION_PATTERN}"
    log_info "  Components: ${VERSION_COMPONENT_COUNT}"
    
    kubectl apply -f - <<EOF
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
    description: "Version ${VERSION_PATTERN} - ${VERSION_COMPONENT_COUNT} components for worst-case signing test"
spec:
  displayName: "Version ${VERSION_PATTERN} Dummy Build - ${VERSION_COMPONENT_COUNT} Components"
EOF
    
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
log_info "Base branch: ${BASE_BRANCH}"
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
batch_number=0

# Iterate through each application (product version)
while IFS=: read -r app_name component_count; do
    [ -z "$app_name" ] && continue
    
    # Extract version from app name (with hyphens, not dots for k8s compliance)
    version=$(echo "$app_name" | grep -oP 'v\K[0-9.-]+')
    
    log_info "Creating ${component_count} components for version ${version}..."
    
    # Create components for this version (in batches)
    for (( i=1; i<=component_count; i++ )); do
        # Use realistic component name pattern (cycle through patterns)
        pattern_idx=$(( (i - 1) % ${#COMPONENT_PATTERNS[@]} ))
        base_component_name="${COMPONENT_PATTERNS[$pattern_idx]}"
        
        # Stable component name (no timestamp) for reuse across test runs
        component_name="v${version}-${base_component_name}-$(printf '%02d' $i)"
        
        # Check if component already exists with successful build (unless force rebuild)
        if [ "${FORCE_REBUILD}" != "true" ] && component_has_successful_build "${component_name}" "${NAMESPACE}"; then
            log_info "   ♻️  Reusing existing build: ${component_name}"
            echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
            skipped_count=$((skipped_count + 1))
            total_components=$((total_components + 1))
            continue
        fi
        
        # If component exists but has no successful build, delete it first (zombie component)
        if kubectl get component "${component_name}" -n "${NAMESPACE}" &>/dev/null; then
            log_warning "   🗑️  Deleting zombie component (exists but no successful build): ${component_name}"
            kubectl delete component "${component_name}" -n "${NAMESPACE}" --ignore-not-found=true &>/dev/null || true
            sleep 2  # Give Kubernetes time to fully delete
        fi
        
        echo "${component_name}:${app_name}" >> "${COMPONENT_LIST}"
        
        # Batch control: wait between batches to avoid GitHub API rate limit exhaustion
        # Note: Only applies when creating NEW components (reused components don't trigger PAC/API calls)
        if [ $((created_count % BATCH_SIZE)) -eq 0 ] && [ ${created_count} -gt 0 ]; then
            batch_number=$((batch_number + 1))
            delay_minutes=$((BATCH_DELAY / 60))
            log_info ""
            log_warning "Batch ${batch_number} complete (${created_count} NEW components created, ${skipped_count} reused)"
            log_info "⏳ Waiting ${delay_minutes} minutes (${BATCH_DELAY}s) to avoid GitHub API rate limits..."
            log_info "   This delay only applies to NEW component creation (triggers PAC operations)"
            log_info "   Reused components don't count toward batches or require delays"
            sleep "${BATCH_DELAY}"
            log_info "✅ Resuming component creation..."
            log_info ""
        fi
        
        # Add unique timestamp to force fresh build (no cache reuse)
        unique_id="$(date +%s)-${version}-${i}"
        
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
    build.appstudio.openshift.io/request: "configure-pac"
    test.appstudio.openshift.io/fresh-build: "true"
spec:
  application: ${app_name}
  componentName: ${component_name}
  containerImage: "quay.io/redhat-user-workloads-stage/${NAMESPACE}/${component_name}"
  source:
    git:
      context: ./
      dockerfileUrl: Dockerfile
      revision: ${BASE_BRANCH}
      url: ${BASE_GITHUB_URL}
EOF
        
        created_count=$((created_count + 1))
        total_components=$((total_components + 1))
        
        # Progress update every batch
        if (( total_components % BATCH_SIZE == 0 )); then
            log_info "   Progress: ${total_components} components created..."
            sleep 1  # Brief pause to avoid overwhelming API server
        fi
    done
    
    log_success "  ✓ Created ${component_count} components for version ${version}"
    
done < "${TEMP_DIR}/applications.txt"

echo "" >&2
if [ ${skipped_count} -gt 0 ]; then
    log_success "Created ${created_count} new components across ${PRODUCT_VERSIONS} product versions"
    log_info "   ♻️  Reused ${skipped_count} existing components with successful builds"
    log_info "   📊 Total: ${total_components} components (${created_count} new + ${skipped_count} reused)"
else
    log_success "Created ${created_count} total components across ${PRODUCT_VERSIONS} product versions"
fi

# Update COMPONENT_COUNT to match actual created count (may differ due to variance)
COMPONENT_COUNT=${total_components}

# ============================================================================
# Step 3: Wait for Builds to Start
# ============================================================================

# Skip build monitoring if all components were reused
if [ ${created_count} -eq 0 ]; then
    log_section "♻️  Step 3/5: Skipping Build Wait (All Components Reused)"
    log_info "All ${total_components} components already have successful builds"
    log_info "Proceeding directly to image digest extraction..."
    echo "" >&2
else
    log_section "⏳ Step 3/5: Waiting for Builds to Initialize"
    log_info "Waiting for Konflux to detect components and trigger builds..."
    log_info "This typically takes 30-60 seconds..."
    log_info "   New components: ${created_count}"
    log_info "   Reused components: ${skipped_count}"

    sleep 60

    # Check how many builds have started (using the multi-version-build label)
    initial_builds=$(kubectl get pipelinerun -n "${NAMESPACE}" \
        -l "test.appstudio.openshift.io/type=multi-version-build" \
        -l "pipelines.appstudio.openshift.io/type=build" \
        --no-headers 2>/dev/null | wc -l || echo "0")

    log_info "Detected ${initial_builds} PipelineRuns starting"

    if [ "${initial_builds}" -eq 0 ]; then
        log_warning "No builds detected yet. Waiting additional 30 seconds..."
        sleep 30
    fi
fi

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
            -o jsonpath='{.status.containerImage}' 2>/dev/null || echo "")
        
        if [ -z "$image_ref" ] || [[ "$image_ref" != *"@sha256:"* ]]; then
            # Try PipelineRun as fallback
            image_ref=$(kubectl get pipelinerun -n "${NAMESPACE}" \
                -l "appstudio.openshift.io/component=${component_name}" \
                -l "pipelines.appstudio.openshift.io/type=build" \
                --sort-by=.metadata.creationTimestamp \
                -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Succeeded" && @.status=="True")])].status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null | tail -1 || echo "")
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
        log_error "This indicates the components don't have successful builds despite being 'reused'"
        log_error "Try running with FORCE_REBUILD=true to rebuild all components"
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

    # Verify COMPONENT_LIST file exists and has content
    if [ ! -f "${COMPONENT_LIST}" ]; then
        log_error "COMPONENT_LIST file not found: ${COMPONENT_LIST}"
        exit 1
    fi
    
    component_list_count=$(wc -l < "${COMPONENT_LIST}" || echo "0")
    if [ "${component_list_count}" -eq 0 ]; then
        log_error "COMPONENT_LIST file is empty: ${COMPONENT_LIST}"
        exit 1
    fi
    
    log_info "   Component list file: ${COMPONENT_LIST} (${component_list_count} entries)"

    START_TIME=$(date +%s)
    COMPLETED=0
    FAILED=0

    while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    # Check build status for all components
    COMPLETED=0
    FAILED=0
    RUNNING=0
    PENDING=0
    TOTAL_BUILDS=0
    COMPONENTS_CHECKED=0
    
    while IFS=: read -r component_name app_name; do
        [ -z "$component_name" ] && continue
        
        COMPONENTS_CHECKED=$((COMPONENTS_CHECKED + 1))
        
        # Get latest PipelineRun for this component
        plr_status=$(kubectl get pipelinerun -n "${NAMESPACE}" \
            -l "appstudio.openshift.io/component=${component_name}" \
            -l "pipelines.appstudio.openshift.io/type=build" \
            --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{.items[-1].status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
        
        if [ -z "$plr_status" ]; then
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
    done < "${COMPONENT_LIST}"
    
    # Debug: Check if we actually processed components
    if [ ${COMPONENTS_CHECKED} -eq 0 ]; then
        log_error "No components were checked! COMPONENT_LIST might be unreadable"
        log_error "File: ${COMPONENT_LIST}"
        log_error "Exists: $([ -f "${COMPONENT_LIST}" ] && echo YES || echo NO)"
        log_error "Content sample: $(head -3 "${COMPONENT_LIST}" 2>&1 || echo 'ERROR')"
        exit 1
    fi
    
    # Calculate progress percentage
    TOTAL_DONE=$((COMPLETED + FAILED))
    PROGRESS_PCT=$((TOTAL_DONE * 100 / COMPONENT_COUNT))
    
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
        log_info "   Completed: ${COMPLETED}/${COMPONENT_COUNT}"
        log_info "   Failed: ${FAILED}"
        log_info "   Still running/pending: $((COMPONENT_COUNT - TOTAL_DONE))"
        exit 1
    fi
    
    # Check if we're done (all builds completed or failed)
    if [ $TOTAL_DONE -ge $COMPONENT_COUNT ]; then
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
fi

# Check if we have enough successful builds
MIN_SUCCESS=$((COMPONENT_COUNT * 90 / 100))  # 90% threshold
if [ ${COMPLETED} -lt ${MIN_SUCCESS} ]; then
    log_error "Insufficient successful builds: ${COMPLETED}/${COMPONENT_COUNT} (need at least ${MIN_SUCCESS})"
    log_info "Review failed builds:"
    log_info "   kubectl get pipelinerun -n ${NAMESPACE} -l test.appstudio.openshift.io/type=multi-version-build"
    exit 1
fi

# ============================================================================
# Step 5: Extract Image Digests
# ============================================================================

log_section "📋 Step 5/5: Extracting Image Digests"
log_info "Collecting container image references from successful builds..."

SUCCESS_COUNT=0
> "${OUTPUT_FILE}"

# Create a temporary file to track per-version statistics
> "${TEMP_DIR}/version-stats.txt"

while IFS=: read -r component_name app_name; do
    [ -z "$component_name" ] && continue
    
    # Try 1: Get container image from component status (preferred, set after successful build)
    image_ref=$(kubectl get component "${component_name}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.containerImage}' 2>/dev/null || echo "")
    
    # Try 2: If status.containerImage is empty, get from latest successful PipelineRun
    if [ -z "$image_ref" ] || [[ "$image_ref" != *"@sha256:"* ]]; then
        image_ref=$(kubectl get pipelinerun -n "${NAMESPACE}" \
            -l "appstudio.openshift.io/component=${component_name}" \
            -l "pipelines.appstudio.openshift.io/type=build" \
            --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Succeeded" && @.status=="True")])].status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null | tail -1 || echo "")
    fi
    
    # Validate image reference format
    if [ -n "$image_ref" ] && [[ "$image_ref" == *"@sha256:"* ]]; then
        echo "${image_ref}" >> "${OUTPUT_FILE}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        # Track per-version stats
        version=$(echo "$app_name" | grep -oP 'v\K[0-9.]+' || echo "unknown")
        echo "${version}" >> "${TEMP_DIR}/version-stats.txt"
        
        if (( SUCCESS_COUNT % 50 == 0 )); then
            log_info "   Extracted ${SUCCESS_COUNT}/${COMPLETED} digests..."
        fi
    fi
done < "${COMPONENT_LIST}"

echo "" >&2
log_section "✅ Build Complete - Fresh Images Ready"
log_success "Successfully extracted ${SUCCESS_COUNT} fresh image digests"
log_info "   Multi-version: ${PRODUCT_VERSIONS} versions × ~${COMPONENTS_PER_VERSION} components"
log_info "   Output file: ${OUTPUT_FILE}"
log_info "   Namespace: ${NAMESPACE}"
echo "" >&2

log_info "📊 Distribution by product version:"
sort "${TEMP_DIR}/version-stats.txt" | uniq -c | while read -r count version; do
    log_info "   Version ${version}: ${count} images"
done
echo "" >&2

log_info "🔍 Sample images (first 5):"
head -5 "${OUTPUT_FILE}" | while read -r img; do
    echo "   ${img}" >&2
done
echo "   ..." >&2
echo "" >&2

log_info "⚠️  IMPORTANT: These images are fresh builds with ZERO Red Hat signatures"
log_info "   Expected signing performance:"
log_info "     • Total digests to sign: ~$((SUCCESS_COUNT * 3)) (${SUCCESS_COUNT} images × ~3 architectures)"
log_info "     • Signing time: 1-2 hours (NO idempotency benefits)"
log_info "     • This simulates worst-case production release signing at scale"
echo "" >&2

log_info "🧹 Cleanup (optional):"
log_info "   # Delete all product version applications after testing:"
while IFS=: read -r app_name _; do
    [ -z "$app_name" ] && continue
    log_info "   kubectl delete application ${app_name} -n ${NAMESPACE}"
done < "${TEMP_DIR}/applications.txt"
echo "" >&2

# Final validation
if [ ${SUCCESS_COUNT} -lt ${MIN_SUCCESS} ]; then
    log_error "Could not extract enough image digests: ${SUCCESS_COUNT}/${COMPLETED}"
    exit 1
fi

log_success "Fresh build process completed successfully!"
log_info "   Ready for worst-case signing test with ${SUCCESS_COUNT} unsigned images"

exit 0
