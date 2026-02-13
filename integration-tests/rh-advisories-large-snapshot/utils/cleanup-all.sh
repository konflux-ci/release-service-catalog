#!/usr/bin/env bash
set -euo pipefail

# Comprehensive cleanup script for rh-advisories-large-snapshot test
# Cleans up: Components, Applications, GitHub branches, PipelineRuns, Releases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-dev-release-team-tenant}"
MANAGED_NAMESPACE="${MANAGED_NAMESPACE:-managed-release-team-tenant}"
BASE_REPO="${BASE_REPO:-hacbs-release-tests/e2e-base}"
DRY_RUN="${DRY_RUN:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 COMPREHENSIVE CLEANUP - rh-advisories-large-snapshot"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Namespace:         ${NAMESPACE}"
echo "Managed Namespace: ${MANAGED_NAMESPACE}"
echo "GitHub Repo:       ${BASE_REPO}"
echo "Dry Run:           ${DRY_RUN}"
echo ""

if [ "${DRY_RUN}" = "true" ]; then
    log_warning "DRY RUN MODE - No actual deletions will be performed"
    echo ""
fi

# Auto-confirm (no interactive prompt)
if [ "${DRY_RUN}" != "true" ]; then
    log_warning "Starting automatic cleanup of ALL test resources..."
    echo ""
fi

cleanup_count=0

# ============================================================================
# 1. CLEANUP KUBERNETES RESOURCES
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  Kubernetes Resources"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Applications (with label)
log_info "Finding Applications..."
apps=$(kubectl get application -n "${NAMESPACE}" \
    -l "test.appstudio.openshift.io/type=multi-version-build" \
    --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$apps" ]; then
    app_count=$(echo "$apps" | wc -l)
    log_info "Found $app_count application(s)"
    
    if [ "${DRY_RUN}" != "true" ]; then
        echo "$apps" | while read -r app; do
            echo "  Deleting application: $app"
            kubectl delete application "$app" -n "${NAMESPACE}" --wait=false 2>/dev/null || true
            cleanup_count=$((cleanup_count + 1))
        done
        log_success "Deleted $app_count application(s)"
    else
        echo "$apps" | sed 's/^/  - /'
    fi
else
    log_info "No applications found"
fi

# Components (with label or name pattern)
log_info "Finding Components..."
components=$(kubectl get component -n "${NAMESPACE}" \
    -l "test.appstudio.openshift.io/type=multi-version-build" \
    --no-headers 2>/dev/null | awk '{print $1}' || echo "")

# Also find by name pattern (v4-*)
pattern_components=$(kubectl get component -n "${NAMESPACE}" \
    --no-headers 2>/dev/null | awk '{print $1}' | grep "^v4-" || echo "")

all_components=$(echo -e "${components}\n${pattern_components}" | sort -u | grep -v "^$" || echo "")

if [ -n "$all_components" ]; then
    comp_count=$(echo "$all_components" | wc -l)
    log_info "Found $comp_count component(s)"
    
    if [ "${DRY_RUN}" != "true" ]; then
        echo "$all_components" | while read -r comp; do
            echo "  Deleting component: $comp"
            kubectl delete component "$comp" -n "${NAMESPACE}" --wait=false 2>/dev/null || true
            
            # Remove finalizers if stuck
            kubectl patch component "$comp" -n "${NAMESPACE}" \
                --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
            
            cleanup_count=$((cleanup_count + 1))
        done
        log_success "Deleted $comp_count component(s)"
    else
        echo "$all_components" | sed 's/^/  - /'
    fi
else
    log_info "No components found"
fi

# PipelineRuns (from last 7 days, with test label)
log_info "Finding old PipelineRuns..."
old_prs=$(kubectl get pipelinerun -n "${NAMESPACE}" \
    -l "test.appstudio.openshift.io/type=multi-version-build" \
    --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$old_prs" ]; then
    pr_count=$(echo "$old_prs" | wc -l)
    log_info "Found $pr_count old PipelineRun(s)"
    
    if [ "${DRY_RUN}" != "true" ]; then
        echo "$old_prs" | while read -r pr; do
            kubectl delete pipelinerun "$pr" -n "${NAMESPACE}" --wait=false 2>/dev/null || true
            cleanup_count=$((cleanup_count + 1))
        done
        log_success "Deleted $pr_count PipelineRun(s)"
    else
        log_info "(showing first 10)"
        echo "$old_prs" | head -10 | sed 's/^/  - /'
    fi
else
    log_info "No old PipelineRuns found"
fi

# Releases (in managed namespace)
log_info "Finding Releases in managed namespace..."
releases=$(kubectl get release -n "${MANAGED_NAMESPACE}" \
    --no-headers 2>/dev/null | awk '{print $1}' | grep "large-snapshot" || echo "")

if [ -n "$releases" ]; then
    rel_count=$(echo "$releases" | wc -l)
    log_info "Found $rel_count release(s)"
    
    if [ "${DRY_RUN}" != "true" ]; then
        echo "$releases" | while read -r rel; do
            echo "  Deleting release: $rel"
            kubectl delete release "$rel" -n "${MANAGED_NAMESPACE}" --wait=false 2>/dev/null || true
            cleanup_count=$((cleanup_count + 1))
        done
        log_success "Deleted $rel_count release(s)"
    else
        echo "$releases" | sed 's/^/  - /'
    fi
else
    log_info "No releases found"
fi

# ReleasePlanAdmissions
log_info "Finding ReleasePlanAdmissions..."
rpas=$(kubectl get releaseplanadmission -n "${MANAGED_NAMESPACE}" \
    --no-headers 2>/dev/null | awk '{print $1}' | grep "large-snapshot" || echo "")

if [ -n "$rpas" ]; then
    rpa_count=$(echo "$rpas" | wc -l)
    log_info "Found $rpa_count ReleasePlanAdmission(s)"
    
    if [ "${DRY_RUN}" != "true" ]; then
        echo "$rpas" | while read -r rpa; do
            echo "  Deleting: $rpa"
            kubectl delete releaseplanadmission "$rpa" -n "${MANAGED_NAMESPACE}" --wait=false 2>/dev/null || true
            cleanup_count=$((cleanup_count + 1))
        done
        log_success "Deleted $rpa_count ReleasePlanAdmission(s)"
    else
        echo "$rpas" | sed 's/^/  - /'
    fi
else
    log_info "No ReleasePlanAdmissions found"
fi

echo ""

# ============================================================================
# 2. CLEANUP GITHUB BRANCHES
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  GitHub Branches"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    log_warning "GitHub CLI (gh) not found - skipping branch cleanup"
    log_info "Install with: https://cli.github.com/"
else
    # Check if GITHUB_TOKEN is set
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        log_warning "GITHUB_TOKEN not set - skipping branch cleanup"
        log_info "Set GITHUB_TOKEN to enable branch deletion"
    else
        log_info "Finding konflux-ls-* branches in ${BASE_REPO}..."
        
        # List all branches matching pattern
        branches=$(gh api "repos/${BASE_REPO}/git/refs/heads" \
            --jq '.[] | select(.ref | startswith("refs/heads/konflux-ls-")) | .ref' 2>/dev/null | \
            sed 's|refs/heads/||' || echo "")
        
        if [ -n "$branches" ]; then
            branch_count=$(echo "$branches" | wc -l)
            log_info "Found $branch_count branch(es)"
            
            if [ "${DRY_RUN}" != "true" ]; then
                echo "$branches" | while read -r branch; do
                    echo "  Deleting branch: $branch"
                    gh api -X DELETE "repos/${BASE_REPO}/git/refs/heads/${branch}" 2>/dev/null || \
                        log_warning "Failed to delete: $branch"
                    cleanup_count=$((cleanup_count + 1))
                    sleep 0.2  # Rate limiting
                done
                log_success "Deleted $branch_count branch(es)"
            else
                log_info "(showing first 20)"
                echo "$branches" | head -20 | sed 's/^/  - /'
            fi
        else
            log_info "No konflux-ls-* branches found"
        fi
    fi
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "${DRY_RUN}" = "true" ]; then
    log_info "Dry run complete - no resources were deleted"
    echo ""
    log_info "Run without DRY_RUN=true to perform actual cleanup:"
    echo "  ./utils/cleanup-all.sh"
else
    log_success "Cleanup complete!"
    echo ""
    log_info "Cleaned up $cleanup_count resources"
    echo ""
    log_info "Next steps:"
    echo "  1. Wait 1-2 minutes for Kubernetes finalizers"
    echo "  2. Verify: kubectl get components -n ${NAMESPACE}"
    echo "  3. Run test: ./test.sh"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
