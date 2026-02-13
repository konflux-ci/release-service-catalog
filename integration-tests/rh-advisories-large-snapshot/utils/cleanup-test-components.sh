#!/bin/bash
set -euo pipefail

# ============================================================================
# cleanup-test-components.sh - Safely clean up test components and applications
# ============================================================================
#
# PURPOSE:
#   Clean up all test Applications and Components (both fresh builds and reused)
#
# USAGE:
#   ./cleanup-test-components.sh [namespace] [options]
#
# OPTIONS:
#   --dry-run           : Show what would be deleted without deleting
#   --force             : Skip confirmation prompt
#   --older-than HOURS  : Only delete resources older than N hours (default: 0 = all)
#   --app-prefix PREFIX : Only delete apps matching prefix (default: large-snapshot-build)
#
# EXAMPLES:
#   # Dry run to see what would be deleted
#   ./cleanup-test-components.sh dev-release-team-tenant --dry-run
#
#   # Delete all test components older than 24 hours
#   ./cleanup-test-components.sh dev-release-team-tenant --older-than 24
#
#   # Delete specific test run by application prefix
#   ./cleanup-test-components.sh dev-release-team-tenant --app-prefix large-snapshot-build-v4-15
#
# ============================================================================

# ============================================================================
# Configuration
# ============================================================================

NAMESPACE="${1:-dev-release-team-tenant}"
DRY_RUN=false
FORCE=false
OLDER_THAN_HOURS=0
APP_PREFIX=""  # Empty = match both "dummy-build" and "large-snapshot-build"

# Parse options
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --older-than)
            OLDER_THAN_HOURS="$2"
            shift 2
            ;;
        --app-prefix)
            APP_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Safety Labels - Only delete resources with these labels
# ============================================================================

SAFETY_LABEL="test.appstudio.openshift.io/type=multi-version-build"
SAFETY_PURPOSE_LABEL="test.appstudio.openshift.io/purpose=worst-case-signing-test"

# ============================================================================
# Functions
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

# ============================================================================
# Main
# ============================================================================

log_section "🧹 Test Components Cleanup"
log_info "Namespace: ${NAMESPACE}"
if [ -n "${APP_PREFIX}" ]; then
    log_info "App prefix: ${APP_PREFIX}-*"
else
    log_info "App prefix: * (all test builds: dummy-build-*, large-snapshot-build-*)"
fi
log_info "Safety label: ${SAFETY_LABEL}"

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No resources will be deleted"
fi

echo "" >&2

# Check namespace exists
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    log_error "Namespace '${NAMESPACE}' does not exist or is not accessible"
    exit 1
fi

# ============================================================================
# Find Applications to Delete
# ============================================================================

log_section "🔍 Finding Applications"

# Build kubectl selector
APP_SELECTOR="-l ${SAFETY_LABEL}"

# Get all matching applications
APPS=$(kubectl get application -n "${NAMESPACE}" \
    ${APP_SELECTOR} \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null || echo "")

if [ -z "$APPS" ]; then
    log_info "No applications found matching criteria"
    exit 0
fi

# Filter by prefix and age
NOW_EPOCH=$(date +%s)
OLDER_THAN_SECONDS=$((OLDER_THAN_HOURS * 3600))

APPS_TO_DELETE=()
APPS_TO_DELETE_COUNT=0

while IFS=$'\t' read -r app_name creation_time; do
    [ -z "$app_name" ] && continue
    
    # Check prefix (if specified)
    if [ -n "${APP_PREFIX}" ]; then
        if [[ ! "$app_name" =~ ^${APP_PREFIX}- ]]; then
            continue
        fi
    else
        # No prefix specified - match common test prefixes
        if [[ ! "$app_name" =~ ^(dummy-build|large-snapshot-build)- ]]; then
            continue
        fi
    fi
    
    # Check age if specified
    if [ "$OLDER_THAN_HOURS" -gt 0 ]; then
        creation_epoch=$(date -d "$creation_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$creation_time" +%s 2>/dev/null || echo "0")
        age_seconds=$((NOW_EPOCH - creation_epoch))
        
        if [ "$age_seconds" -lt "$OLDER_THAN_SECONDS" ]; then
            log_info "Skipping $app_name (too recent: ${age_seconds}s old, need ${OLDER_THAN_SECONDS}s)"
            continue
        fi
    fi
    
    APPS_TO_DELETE+=("$app_name")
    APPS_TO_DELETE_COUNT=$((APPS_TO_DELETE_COUNT + 1))
    
    # Get component count for this app
    component_count=$(kubectl get component -n "${NAMESPACE}" \
        -l "appstudio.application=${app_name}" \
        --no-headers 2>/dev/null | wc -l || echo "0")
    
    log_info "Found: $app_name ($component_count components)"
done <<< "$APPS"

echo "" >&2

if [ "$APPS_TO_DELETE_COUNT" -eq 0 ]; then
    log_info "No applications match deletion criteria"
    exit 0
fi

log_section "📊 Cleanup Summary"
log_info "Applications to delete: ${APPS_TO_DELETE_COUNT}"

# Calculate total components
TOTAL_COMPONENTS=$(kubectl get component -n "${NAMESPACE}" \
    ${APP_SELECTOR} \
    --no-headers 2>/dev/null | wc -l || echo "0")

log_info "Total components to delete: ${TOTAL_COMPONENTS} (cascade delete via Applications)"

echo "" >&2

# ============================================================================
# Safety Confirmation
# ============================================================================

if [ "$DRY_RUN" = true ]; then
    log_section "🔍 Dry Run - Would Delete:"
    for app in "${APPS_TO_DELETE[@]}"; do
        echo "  - Application: $app"
    done
    log_success "Dry run complete. Use without --dry-run to actually delete."
    exit 0
fi

if [ "$FORCE" = false ]; then
    log_warning "This will delete ${APPS_TO_DELETE_COUNT} applications and ${TOTAL_COMPONENTS} components"
    log_warning "Applications to delete:"
    for app in "${APPS_TO_DELETE[@]}"; do
        echo "    - $app" >&2
    done
    echo "" >&2
    echo -n "⚠️  Are you sure? Type 'yes' to confirm: " >&2
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
fi

# ============================================================================
# Perform Cleanup
# ============================================================================

log_section "🗑️  Deleting Resources"

deleted_count=0
failed_count=0

for app in "${APPS_TO_DELETE[@]}"; do
    log_info "Deleting application: $app (and its components)..."
    
    if kubectl delete application -n "${NAMESPACE}" "$app" 2>/dev/null; then
        deleted_count=$((deleted_count + 1))
    else
        log_error "Failed to delete application: $app"
        failed_count=$((failed_count + 1))
    fi
done

echo "" >&2

# ============================================================================
# Summary
# ============================================================================

log_section "📊 Cleanup Complete"
log_success "Deleted: ${deleted_count} applications"

if [ "$failed_count" -gt 0 ]; then
    log_error "Failed: ${failed_count} applications"
    exit 1
fi

log_info "All components have been cascade-deleted via their Applications"
log_success "Cleanup successful!"
