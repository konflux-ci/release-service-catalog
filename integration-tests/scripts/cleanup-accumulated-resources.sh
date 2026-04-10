#!/usr/bin/env bash
# Script to clean up accumulated resources from integration tests
# This helps prevent ExceededQuota failures and resource accumulation
#
# NOTE: This is a general-purpose cleanup script for all integration tests (label-based).
# For collectors-specific quick cleanup, see: ../collectors/utils/cleanup-resources.sh

set -eo pipefail

# Configuration
DEFAULT_AGE_HOURS=24  # Default: clean resources older than 24 hours
FORCE_MODE=false
DRY_RUN=false

# Parse arguments
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up accumulated resources from integration tests to prevent quota issues.

OPTIONS:
    -a, --age HOURS        Age threshold in hours (default: ${DEFAULT_AGE_HOURS})
    -f, --force            Force cleanup without confirmation
    -d, --dry-run          Show what would be deleted without actually deleting
    -h, --help             Show this help message

EXAMPLES:
    # Clean resources older than 24 hours (default)
    $0

    # Clean resources older than 12 hours
    $0 --age 12

    # Dry run to see what would be deleted
    $0 --dry-run

    # Force cleanup without confirmation
    $0 --force

EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--age)
            # Validate age argument exists and is numeric
            if [ -z "${2:-}" ]; then
                echo "Error: --age requires a numeric value (hours)"
                usage
            fi
            if ! [[ "${2}" =~ ^[0-9]+$ ]]; then
                echo "Error: --age must be a positive integer (got: '${2}')"
                usage
            fi
            if [ "${2}" -lt 1 ]; then
                echo "Error: --age must be at least 1 hour (got: ${2})"
                usage
            fi
            DEFAULT_AGE_HOURS="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done

# Convert hours to minutes for consistency with existing functions
AGE_MINUTES=$((DEFAULT_AGE_HOURS * 60))
CUTOFF_TIME=$(date -d "${AGE_MINUTES} minutes ago" +%s)

echo "🧹 Integration Test Resource Cleanup"
echo "======================================="
echo "Age threshold: ${DEFAULT_AGE_HOURS} hours (${AGE_MINUTES} minutes)"
echo "Cutoff time: $(date -d "${AGE_MINUTES} minutes ago")"
echo "Dry run: ${DRY_RUN}"
echo ""

# Namespaces to check
NAMESPACES="dev-release-team-tenant managed-release-team-tenant"

# Count resources to be cleaned
total_resources=0
declare -A resource_counts

# Function to check and count resources
count_old_resources() {
    local kind=$1
    local namespace=$2
    local label_selector=${3:-""}
    
    local selector_arg=""
    if [ -n "$label_selector" ]; then
        selector_arg="-l ${label_selector}"
    fi
    
    local count=0
    if kubectl get "$kind" -n "$namespace" $selector_arg --no-headers 2>/dev/null | \
       awk -v cutoff="$CUTOFF_TIME" '{
           # Get creation timestamp (usually column 5 or 6 depending on resource type)
           for (i=1; i<=NF; i++) {
               if ($i ~ /^[0-9]+[smhd]$/) {
                   # Parse age format (e.g., "5h", "2d")
                   cmd = "date -d \"" $i " ago\" +%s"
                   cmd | getline created_at
                   close(cmd)
                   if (created_at < cutoff) {
                       print $1
                   }
                   break
               }
           }
       }' | grep -c .; then
        count=$?
    fi
    
    echo "$count"
}

# Function to delete old resources
delete_old_resources() {
    local kind=$1
    local namespace=$2
    local label_selector=${3:-""}
    
    local selector_arg=""
    if [ -n "$label_selector" ]; then
        selector_arg="-l ${label_selector}"
    fi
    
    echo "🔍 Checking ${kind} in namespace ${namespace}..."
    
    local resources_to_delete
    resources_to_delete=$(kubectl get "$kind" -n "$namespace" $selector_arg \
        -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{.metadata.creationTimestamp}}{{"\n"}}{{end}}' 2>/dev/null | \
        awk -v cutoff_time="$CUTOFF_TIME" '{
            cmd = "date -d " $2 " +%s"
            cmd | getline created_at
            close(cmd)
            if (created_at < cutoff_time) {
                print $1
            }
        }')
    
    if [ -n "$resources_to_delete" ]; then
        local count=$(echo "$resources_to_delete" | wc -l)
        echo "  Found $count old ${kind}(s) to delete"
        
        while read -r resource_name; do
            if [ -n "$resource_name" ]; then
                if [ "$DRY_RUN" = true ]; then
                    echo "    [DRY RUN] Would delete: ${kind}/${resource_name}"
                else
                    echo "    Deleting: ${kind}/${resource_name}"
                    kubectl delete "$kind" "$resource_name" -n "$namespace" --timeout=30s 2>/dev/null || \
                        echo "      ⚠️  Failed to delete ${kind}/${resource_name}"
                fi
                total_resources=$((total_resources + 1))
            fi
        done <<< "$resources_to_delete"
    else
        echo "  ✅ No old ${kind}(s) found"
    fi
}

# Confirmation prompt unless force mode or dry run
if [ "$FORCE_MODE" = false ] && [ "$DRY_RUN" = false ]; then
    echo "⚠️  This will delete resources older than ${DEFAULT_AGE_HOURS} hours."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "🔍 Scanning for resources to clean up..."
echo ""

# Clean up InternalRequests (these can accumulate and contribute to quota issues)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 InternalRequests Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if kubectl api-resources | grep -q "^internalrequests"; then
    for namespace in $NAMESPACES; do
        delete_old_resources "internalrequest" "$namespace"
    done
else
    echo "⚠️  InternalRequest CRD not found on cluster"
fi
echo ""

# Clean up PipelineRuns
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 PipelineRuns Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    delete_old_resources "pipelinerun" "$namespace"
done
echo ""

# Clean up TaskRuns (child resources of PipelineRuns)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 TaskRuns Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    delete_old_resources "taskrun" "$namespace"
done
echo ""

# NOTE: Snapshots are intentionally NOT cleaned up as they:
# - May be referenced by Releases or other tests
# - Are immutable and relatively lightweight
# - Deletion could break concurrent or dependent tests

# Clean up Releases
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Releases Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    delete_old_resources "release" "$namespace"
done
echo ""

# Clean up Applications (with originating-tool label)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Applications Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    # Look for applications with originating-tool label (from e2e tests)
    if kubectl get application -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
        delete_old_resources "application" "$namespace" "originating-tool"
    else
        echo "  ✅ No applications found in $namespace"
    fi
done
echo ""

# Clean up Components (with originating-tool label)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Components Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    if kubectl get component -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
        delete_old_resources "component" "$namespace" "originating-tool"
    else
        echo "  ✅ No components found in $namespace"
    fi
done
echo ""

# Clean up ReleasePlans
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 ReleasePlans Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    if kubectl get releaseplan -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
        delete_old_resources "releaseplan" "$namespace" "originating-tool"
    else
        echo "  ✅ No release plans found in $namespace"
    fi
done
echo ""

# Clean up ReleasePlanAdmissions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 ReleasePlanAdmissions Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for namespace in $NAMESPACES; do
    if kubectl get releaseplanadmission -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
        delete_old_resources "releaseplanadmission" "$namespace" "originating-tool"
    else
        echo "  ✅ No release plan admissions found in $namespace"
    fi
done
echo ""

# SAFETY NOTES - Resources intentionally NOT cleaned:
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 Resources Excluded for Safety"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "The following resources are NOT cleaned to prevent breaking shared infrastructure:"
echo "  - ImageRepositories: Lack reliable ownership labels, cleaned per-test automatically"
echo "  - Snapshots: May be referenced by other tests/releases (immutable)"
echo "  - ClusterRoles: Cluster-wide resources that may be shared"
echo "  - Secrets: May contain infrastructure secrets that persist across tests"
echo "  - ServiceAccounts: May be shared infrastructure"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Cleanup Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN: Would have deleted $total_resources resources"
else
    echo "✅ Deleted $total_resources resources"
fi

# Check current InternalRequest count
echo ""
echo "📈 Current InternalRequest counts:"
if kubectl api-resources | grep -q "^internalrequests"; then
    for namespace in $NAMESPACES; do
        local count=$(kubectl get internalrequest -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        echo "  ${namespace}: ${count}"
        if [ "$count" -gt 900 ]; then
            echo "    ⚠️  WARNING: Approaching quota limit (1024)!"
        fi
    done
else
    echo "  ⚠️  InternalRequest CRD not found"
fi

echo ""
if [ "$DRY_RUN" = false ]; then
    echo "✅ Cleanup completed successfully"
else
    echo "🔍 Dry run completed. Run without --dry-run to actually delete resources."
fi
