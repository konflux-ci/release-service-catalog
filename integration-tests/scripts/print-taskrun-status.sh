#!/usr/bin/env bash
#
# Monitor TaskRuns within a PipelineRun execution
# Usage: ./monitor-taskruns.sh [PIPELINERUN_NAME] [NAMESPACE]
#

set -euo pipefail

# Color constants (disable if NO_COLOR is set or if not outputting to a terminal)
if [[ -n "${NO_COLOR:-}" ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    WHITE=''
    BOLD=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
fi

# Function to colorize status text
colorize_status() {
    local line="$1"
    
    # Replace status keywords with colored versions
    line=${line//Succeeded/${GREEN}Succeeded${NC}}
    line=${line//Failed/${RED}Failed${NC}}
    line=${line//Running/${YELLOW}Running${NC}}
    line=${line//Started/${YELLOW}Started${NC}}
    line=${line//Pending/${BLUE}Pending${NC}}
    line=${line//Unknown/${PURPLE}Unknown${NC}}
    line=${line//Completed/${CYAN}Completed${NC}}
    line=${line//TaskRunTimeout/${RED}TaskRunTimeout${NC}}
    line=${line//TaskRunCancelled/${RED}TaskRunCancelled${NC}}
    line=${line//PipelineRunTimeout/${RED}PipelineRunTimeout${NC}}
    line=${line//PipelineRunCancelled/${RED}PipelineRunCancelled${NC}}
    line=${line//TaskRunImagePullFailed/${RED}TaskRunImagePullFailed${NC}}
    line=${line//TaskRunResourceVerificationFailed/${RED}TaskRunResourceVerificationFailed${NC}}
    line=${line//TaskRunStopSidecarFailed/${RED}TaskRunStopSidecarFailed${NC}}
    line=${line//CreateContainerConfigError/${RED}CreateContainerConfigError${NC}}
    line=${line//ExceededResourceQuota/${RED}ExceededResourceQuota${NC}}
    line=${line//ExceededNodeResources/${RED}ExceededNodeResources${NC}}
    line=${line//TaskRunValidationFailed/${RED}TaskRunValidationFailed${NC}}
    
    # Also colorize some common step statuses
    line=${line//Not started/${BLUE}Not started${NC}}
    line=${line//Step:/${BOLD}Step:${NC}}
    line=${line//Duration:/${BOLD}Duration:${NC}}
    
    echo -e "$line"
}

PIPELINERUN_NAME=${1:-""}
NAMESPACE=${2:-"default"}

if [ -z "$PIPELINERUN_NAME" ]; then
    echo "Usage: $0 <pipelinerun-name> [namespace] [command]"
    echo "Example: $0 my-pipeline-run-abc123 default status"
    echo ""
    echo -e "💡 ${BOLD}Available commands:${NC}"
    echo -e "  ${CYAN}status${NC}     # Show current status (default)"
    echo -e "  ${CYAN}compact${NC}    # Show compact status summary (Running: 1, Pending: 2, etc.)"
    echo -e "  ${CYAN}raw${NC}        # Show raw TaskRun data without headers"
    echo -e "  ${CYAN}help${NC}       # Show this help"
    exit 1
fi

# Function to show header
show_header() {
    echo -e "🔍 ${BOLD}Monitoring TaskRuns for PipelineRun:${NC} ${CYAN}$PIPELINERUN_NAME${NC} ${BOLD}in namespace:${NC} ${YELLOW}$NAMESPACE${NC}"
    echo "=================================================================="
}

# Function to get TaskRun status for a specific PipelineRun
get_taskrun_status() {
    local show_header=${1:-true}
    
    if [[ "$show_header" == "true" ]]; then
        echo -e "📊 ${BOLD}Current TaskRun status:${NC}"
        echo ""
    fi
    
    kubectl get taskruns -n "$NAMESPACE" \
        -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" \
        -o json | \
    jq -r '
        .items | 
        map({
            name: .metadata.name,
            taskName: (.metadata.labels["tekton.dev/pipelineTask"] // "unknown"),
            startTime: .status.startTime,
            completionTime: .status.completionTime,
            status: (.status.conditions[0].reason // "Unknown"),
            sortKey: (
                if .status.startTime then .status.startTime
                elif (.status.conditions[0].reason // "Unknown") == "Running" then "9999-12-31T23:59:59Z"
                else "0000-01-01T00:00:00Z"
                end
            )
        }) |
        sort_by(.sortKey) |
        .[] |
        "\(.taskName) (\(.name)): \(.status) | Started: \(.startTime // "Not started") | Completed: \(.completionTime // "Running")"
    ' | while IFS= read -r line; do
        colorize_status "$line"
    done
}

# Function to get compact TaskRun status summary
get_compact_status() {
    # Get all TaskRuns and their statuses
    local status_data
    status_data=$(kubectl get taskruns -n "$NAMESPACE" \
        -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" \
        -o json | \
    jq -r '.items[] | .status.conditions[0].reason // "Unknown"' | sort)
    
    if [ -z "$status_data" ]; then
        echo "No TaskRuns found"
        return
    fi
    
    # Count occurrences of each status
    local succeeded_count pending_count running_count failed_count unknown_count
    local timeout_count cancelled_count other_count
    
    succeeded_count=$(echo "$status_data" | grep -c "^Succeeded$" 2>/dev/null || echo "0")
    succeeded_count=${succeeded_count//[^0-9]/}  # Remove any non-numeric characters
    
    pending_count=$(echo "$status_data" | grep -c "^Pending$" 2>/dev/null || echo "0")
    pending_count=${pending_count//[^0-9]/}
    
    running_count=$(echo "$status_data" | grep -c "^Running$" 2>/dev/null || echo "0")
    running_count=${running_count//[^0-9]/}
    
    failed_count=$(echo "$status_data" | grep -c "^Failed$" 2>/dev/null || echo "0")
    failed_count=${failed_count//[^0-9]/}
    
    unknown_count=$(echo "$status_data" | grep -c "^Unknown$" 2>/dev/null || echo "0")
    unknown_count=${unknown_count//[^0-9]/}
    
    timeout_count=$(echo "$status_data" | grep -c "Timeout" 2>/dev/null || echo "0")
    timeout_count=${timeout_count//[^0-9]/}
    
    cancelled_count=$(echo "$status_data" | grep -c "Cancelled" 2>/dev/null || echo "0")
    cancelled_count=${cancelled_count//[^0-9]/}
    
    # Count other failure states
    other_count=$(echo "$status_data" | grep -E "(ImagePullFailed|ResourceVerificationFailed|ValidationFailed|ConfigError|QuotaExceeded)" 2>/dev/null | wc -l 2>/dev/null || echo "0")
    other_count=${other_count//[^0-9]/}
    
    # Ensure all counts are valid integers (default to 0)
    succeeded_count=${succeeded_count:-0}
    pending_count=${pending_count:-0}
    running_count=${running_count:-0}
    failed_count=${failed_count:-0}
    unknown_count=${unknown_count:-0}
    timeout_count=${timeout_count:-0}
    cancelled_count=${cancelled_count:-0}
    other_count=${other_count:-0}
    
    # Build the compact status line
    local status_parts=()
    
    # Add non-zero counts in logical order
    [ "$running_count" -gt 0 ] && status_parts+=("${YELLOW}Running${NC}: $running_count")
    [ "$pending_count" -gt 0 ] && status_parts+=("${BLUE}Pending${NC}: $pending_count") 
    [ "$succeeded_count" -gt 0 ] && status_parts+=("${GREEN}Succeeded${NC}: $succeeded_count")
    [ "$failed_count" -gt 0 ] && status_parts+=("${RED}Failed${NC}: $failed_count")
    [ "$timeout_count" -gt 0 ] && status_parts+=("${RED}Timeout${NC}: $timeout_count")
    [ "$cancelled_count" -gt 0 ] && status_parts+=("${RED}Cancelled${NC}: $cancelled_count")
    [ "$other_count" -gt 0 ] && status_parts+=("${RED}Other Errors${NC}: $other_count")
    [ "$unknown_count" -gt 0 ] && status_parts+=("${PURPLE}Unknown${NC}: $unknown_count")
    
    # If no TaskRuns, show that
    if [ ${#status_parts[@]} -eq 0 ]; then
        echo "No TaskRuns found"
        return
    fi
    
    # Join the parts with commas and spaces
    local output=""
    local first=true
    for part in "${status_parts[@]}"; do
        if [ "$first" = true ]; then
            output="$part"
            first=false
        else
            output="$output, $part"
        fi
    done
    echo -e "$output"
}

# Main execution
case "${3:-status}" in
    "compact")
        # Skip headers for compact output - just show the summary line
        get_compact_status
        ;;
    "raw")
        # Skip all headers for raw output - just show the TaskRun data
        get_taskrun_status false
        ;;
    "help"|"-h"|"--help")
        show_header
        echo -e "💡 ${BOLD}Available commands:${NC}"
        echo -e "  ${CYAN}$0 $PIPELINERUN_NAME $NAMESPACE status${NC}     # Show current status (default)"
        echo -e "  ${CYAN}$0 $PIPELINERUN_NAME $NAMESPACE compact${NC}    # Show compact status summary"
        echo -e "  ${CYAN}$0 $PIPELINERUN_NAME $NAMESPACE raw${NC}        # Show raw TaskRun data without headers"
        echo -e "  ${CYAN}$0 $PIPELINERUN_NAME $NAMESPACE help${NC}       # Show this help"
        ;;
    "status"|*)
        show_header
        get_taskrun_status true
        ;;
esac
