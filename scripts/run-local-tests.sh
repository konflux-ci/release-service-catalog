#!/bin/bash
# Local Tekton Task Test Runner
# This script runs Tekton task tests locally using the existing test infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/test-results"
MAX_PARALLEL=${MAX_PARALLEL:-1}  # Default to sequential execution

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [TASK_DIRS_OR_FILES...]

Run Tekton task tests locally in a Kind cluster.

OPTIONS:
    --help                      Show this help message
    --remove-compute-resources  Remove compute resources from tasks (useful for resource-constrained environments)
    --trusted-artifacts         Use Trusted Artifacts workflow (default: auto-detect)
    --pvc                       Force PVC-based workflow
    --dry-run                   Show what would be tested without running
    --parallel N                Run N tests in parallel (default: 1)
    --pr-mode                   Use GitHub API + CI-identical change detection
    --cleanup                   Clean up test resources and results after completion
    --verbose                   Enable verbose output

ARGUMENTS:
    TASK_DIRS_OR_FILES  Task directories (e.g., tasks/managed/add-fbc-contribution) 
                        or specific test files (e.g., tasks/*/tests/test-*.yaml)
                        If not provided, will test changed tasks based on git diff

EXAMPLES:
    # Test a specific task
    $0 tasks/managed/add-fbc-contribution

    # Test with parallel execution
    $0 --parallel 3 tasks/managed/add-fbc-contribution

    # Test PR changes (requires GitHub CLI)
    $0 --pr-mode

    # Test a specific test file
    $0 tasks/managed/add-fbc-contribution/tests/test-add-fbc-contribution.yaml

    # Test multiple tasks
    $0 tasks/managed/add-fbc-contribution tasks/internal/update-fbc-catalog-task

    # Test all changed tasks (based on git diff)
    $0

    # Use PVC workflow and remove compute resources
    $0 --pvc --remove-compute-resources tasks/managed/add-fbc-contribution

PREREQUISITES:
    1. Run ./scripts/local-test-setup.sh first to set up the environment
    2. Source .env.testing to configure environment variables
    3. Ensure Kind cluster is running and kubectl context is correct

EOF
}

setup_results_tracking() {
    # Create test-results directory and initialize tracking
    mkdir -p "$RESULTS_DIR"
    chmod 750 "$RESULTS_DIR" 2>/dev/null || true
    
    # Clear previous results
    rm -f "${RESULTS_DIR}"/*.log "${RESULTS_DIR}"/*.status 2>/dev/null || true
    
    log "Results tracking enabled: $RESULTS_DIR"
}

auto_source_environment() {
    # Auto-source .env.testing if it exists and environment is not already set
    if [ -f ".env.testing" ] && [ -z "${KUBECONFIG:-}" ]; then
        log "Auto-sourcing .env.testing..."
        source .env.testing
    fi
}

check_environment() {
    log "Checking test environment..."
    
    # Auto-source environment first
    auto_source_environment
    
    # Check if kubectl context is set to kind cluster
    local current_context
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    if [[ ! "$current_context" =~ ^kind- ]]; then
        error "kubectl context is not set to a Kind cluster: $current_context"
        echo "Run './scripts/local-test-setup.sh' to set up the environment"
        echo "Or manually source: source .env.testing"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot access Kubernetes cluster"
        echo "Make sure your Kind cluster is running: kind get clusters"
        exit 1
    fi
    
    # Check if Tekton is installed
    if ! kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
        error "Tekton is not installed in the cluster"
        echo "Run './scripts/local-test-setup.sh' to set up the environment"
        exit 1
    fi
    
    # Check required tools
    local missing_tools=()
    command -v tkn >/dev/null 2>&1 || missing_tools+=("tkn")
    command -v yq >/dev/null 2>&1 || missing_tools+=("yq")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        echo "Run './scripts/local-test-setup.sh' to install missing tools"
        exit 1
    fi
    
    success "Environment check passed"
}

detect_changed_tasks() {
    log "Detecting changed tasks from git diff..."
    
    # Get changed files related to tasks
    local changed_files
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Get changed files compared to origin/development or main branch
        local base_branch
        if git rev-parse --verify origin/development >/dev/null 2>&1; then
            base_branch="origin/development"
        elif git rev-parse --verify origin/main >/dev/null 2>&1; then
            base_branch="origin/main"
        else
            base_branch="HEAD~1"
        fi
        
        changed_files=$(git diff --name-only "$base_branch"...HEAD | grep "^tasks/" | grep -v "\.md$" || true)
    else
        warn "Not in a git repository, cannot auto-detect changed tasks"
        changed_files=""
    fi
    
    if [ -z "$changed_files" ]; then
        warn "No changed task files detected"
        return 1
    fi
    
    # Extract unique task directories from changed files
    local task_dirs=()
    while IFS= read -r file; do
        if [[ "$file" =~ ^tasks/[^/]+/[^/]+/ ]]; then
            local task_dir
            task_dir=$(echo "$file" | cut -d'/' -f1-3)
            if [[ ! " ${task_dirs[*]} " =~ " ${task_dir} " ]]; then
                task_dirs+=("$task_dir")
            fi
        fi
    done <<< "$changed_files"
    
    if [ ${#task_dirs[@]} -eq 0 ]; then
        warn "No valid task directories found in changed files"
        return 1
    fi
    
    log "Detected changed tasks: ${task_dirs[*]}"
    echo "${task_dirs[@]}"
}

detect_pr_changes() {
    log "Detecting PR changes using GitHub CLI..."
    
    # Check if gh CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        error "GitHub CLI (gh) is required for --pr-mode but not found"
        echo "Install GitHub CLI: https://cli.github.com/"
        exit 1
    fi
    
    # Get base branch from GitHub API
    local base_branch
    base_branch=$(gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null) || {
        error "Failed to get PR information. Are you in a PR branch?"
        echo "Make sure you're on a PR branch and authenticated with GitHub CLI"
        exit 1
    }
    
    # Validate branch name
    if [[ ! "$base_branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        error "Invalid base branch name: $base_branch"
        exit 1
    fi
    
    log "Base branch: $base_branch"
    
    # Get changed files using exact CI logic from .github/workflows/tekton_task_tests.yaml
    local changed_files
    changed_files=$(git diff --name-only "origin/$base_branch"...HEAD 2>/dev/null | grep "^tasks/" | grep -v "\.md$" || true)
    
    if [ -z "$changed_files" ]; then
        warn "No changed task files detected in PR"
        return 1
    fi
    
    # Extract unique task directories (dir_names=true, dir_names_max_depth=3)
    local task_dirs=()
    while IFS= read -r file; do
        if [[ "$file" =~ ^tasks/[^/]+/[^/]+/ ]]; then
            local task_dir
            task_dir=$(echo "$file" | cut -d'/' -f1-3)
            if [[ ! " ${task_dirs[*]} " =~ " ${task_dir} " ]]; then
                task_dirs+=("$task_dir")
            fi
        fi
    done <<< "$changed_files"
    
    if [ ${#task_dirs[@]} -eq 0 ]; then
        warn "No valid task directories found in PR changes"
        return 1
    fi
    
    log "Detected PR changed tasks: ${task_dirs[*]}"
    echo "${task_dirs[@]}"
}

classify_tasks() {
    local test_items=("$@")
    local trusted_artifacts_tasks=()
    local pvc_tasks=()
    
    for item in "${test_items[@]}"; do
        local task_name task_file task_dir
        
        if [[ "$item" == *tests/test-*.yaml ]]; then
            # Extract task info from test file path
            task_dir=$(dirname "$(dirname "$item")")
            task_name=$(basename "$task_dir")
        else
            # Item is a task directory
            task_dir="$item"
            task_name=$(basename "$item")
        fi
        
        task_file="${task_dir}/${task_name}.yaml"
        
        if [ ! -f "$task_file" ]; then
            warn "Task file not found: $task_file"
            continue
        fi
        
        # Check if task supports Trusted Artifacts (uses TA step actions)
        if grep -q "name: use-trusted-artifact\|name: create-trusted-artifact" "$task_file"; then
            trusted_artifacts_tasks+=("$item")
        else
            pvc_tasks+=("$item")
        fi
    done
    
    echo "TRUSTED_ARTIFACTS:${trusted_artifacts_tasks[*]:-}"
    echo "PVC:${pvc_tasks[*]:-}"
}

run_single_test_item() {
    local test_item="$1"
    local workflow_type="$2"
    local test_name
    
    # Input validation with regex pattern
    if [[ ! "$test_item" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        error "Invalid test item path: $test_item"
        return 1
    fi
    
    # Generate test name for results tracking
    if [[ "$test_item" == *tests/test-*.yaml ]]; then
        test_name=$(basename "$test_item" .yaml)
    else
        test_name=$(basename "$test_item")
    fi
    
    local log_file="${RESULTS_DIR}/test-${test_name}-$$.log"
    local status_file="${RESULTS_DIR}/test-${test_name}-$$.status"
    local test_script="${REPO_ROOT}/.github/scripts/test_tekton_tasks.sh"
    local test_args=()
    
    if [ "${REMOVE_COMPUTE_RESOURCES:-false}" = "true" ]; then
        test_args+=("--remove-compute-resources")
    fi
    
    log "Starting test: $test_name (workflow: $workflow_type)"
    
    # Run test based on workflow type
    local test_cmd
    case "$workflow_type" in
        "trusted-artifacts")
            if [ ${#test_args[@]} -gt 0 ]; then
                test_cmd="TEST_ITEMS='$test_item' USE_TRUSTED_ARTIFACTS=true DOCKER_CONFIG_JSON='${DOCKER_CONFIG_JSON:-}' '$test_script' '${test_args[*]}'"
            else
                test_cmd="TEST_ITEMS='$test_item' USE_TRUSTED_ARTIFACTS=true DOCKER_CONFIG_JSON='${DOCKER_CONFIG_JSON:-}' '$test_script'"
            fi
            ;;
        "pvc")
            if [ ${#test_args[@]} -gt 0 ]; then
                test_cmd="TEST_ITEMS='$test_item' '$test_script' '${test_args[*]}'"
            else
                test_cmd="TEST_ITEMS='$test_item' '$test_script'"
            fi
            ;;
        *)
            error "Unknown workflow type: $workflow_type"
            echo "FAILED" > "$status_file"
            return 1
            ;;
    esac
    
    # Execute test with atomic file operations
    local temp_status
    temp_status=$(mktemp)
    if bash -c "$test_cmd" > "$log_file" 2>&1; then
        echo "PASSED" > "$temp_status" && mv "$temp_status" "$status_file"
        success "PASSED: $test_name"
        return 0
    else
        local exit_code=$?
        echo "FAILED" > "$temp_status" && mv "$temp_status" "$status_file"
        error "FAILED: $test_name (exit code: $exit_code)"
        return $exit_code
    fi
}

run_tests_parallel() {
    local force_workflow="$1"
    local trusted_artifacts_tasks="$2"
    local pvc_tasks="$3"
    local max_parallel="$4"
    shift 4
    local test_items=("$@")
    
    # Export functions for parallel execution with unique names
    local function_suffix="$$"
    eval "run_single_test_item_${function_suffix}() { run_single_test_item \"\$@\"; }"
    export -f "run_single_test_item_${function_suffix}" log success error warn
    export RESULTS_DIR REPO_ROOT REMOVE_COMPUTE_RESOURCES DOCKER_CONFIG_JSON
    
    log "Running tests in parallel (max: $max_parallel)..."
    
    # Build test execution list with workflow classification
    local parallel_items=()
    case "$force_workflow" in
        "trusted-artifacts")
            for item in "${test_items[@]}"; do
                parallel_items+=("$item trusted-artifacts")
            done
            ;;
        "pvc")
            for item in "${test_items[@]}"; do
                parallel_items+=("$item pvc")
            done
            ;;
        *)
            # Auto-classify each item
            for item in "${test_items[@]}"; do
                local classification
                classification=$(classify_tasks "$item")
                if echo "$classification" | grep -q "^TRUSTED_ARTIFACTS:.*$item"; then
                    parallel_items+=("$item trusted-artifacts")
                else
                    parallel_items+=("$item pvc")
                fi
            done
            ;;
    esac
    
    # Execute tests in parallel using xargs pattern
    printf '%s\n' "${parallel_items[@]}" | xargs -I {} -P "$max_parallel" bash -c "run_single_test_item_${function_suffix} {}" _
    
    # Cleanup exported functions
    unset -f "run_single_test_item_${function_suffix}"
}

generate_test_summary() {
    log "Generating test summary report..."
    
    local summary_file="${RESULTS_DIR}/summary.txt"
    local passed=0
    local failed=0
    local timeout=0
    local total=0
    
    # Count results from status files
    if ls "${RESULTS_DIR}"/*.status >/dev/null 2>&1; then
        for status_file in "${RESULTS_DIR}"/*.status; do
            ((total++))
            local status
            status=$(cat "$status_file" 2>/dev/null || echo "UNKNOWN")
            case "$status" in
                "PASSED") ((passed++)) ;;
                "FAILED") ((failed++)) ;;
                "TIMEOUT") ((timeout++)) ;;
                *) ((failed++)) ;;
            esac
        done
    fi
    
    # Generate summary report
    {
        echo "=== TEST RESULTS SUMMARY ==="
        echo "Total tests: $total"
        echo "✅ Passed: $passed"
        echo "❌ Failed: $failed"
        echo "⏰ Timeout: $timeout"
        echo
        
        # Show failed test details
        if [ $failed -gt 0 ] || [ $timeout -gt 0 ]; then
            echo "=== FAILED TEST DETAILS ==="
            for status_file in "${RESULTS_DIR}"/*.status; do
                [ -f "$status_file" ] || continue
                local test_name=$(basename "$status_file" .status)
                local status
                status=$(cat "$status_file" 2>/dev/null || echo "UNKNOWN")
                if [ "$status" = "FAILED" ] || [ "$status" = "TIMEOUT" ]; then
                    local log_file="${RESULTS_DIR}/${test_name}.log"
                    echo "--- $test_name ($status) ---"
                    if [ -f "$log_file" ]; then
                        echo "Last 10 lines:"
                        tail -10 "$log_file" 2>/dev/null || echo "No log available"
                    else
                        echo "No log available"
                    fi
                    echo
                fi
            done
        fi
    } > "$summary_file"
    
    # Display summary to console
    cat "$summary_file"
    log "Summary report saved to: $summary_file"
}

run_tests() {
    local test_items=("$@")
    local remove_compute_resources="${REMOVE_COMPUTE_RESOURCES:-false}"
    local force_workflow="${FORCE_WORKFLOW:-}"
    local dry_run="${DRY_RUN:-false}"
    local cleanup="${CLEANUP:-false}"
    local verbose="${VERBOSE:-false}"
    
    if [ ${#test_items[@]} -eq 0 ]; then
        if [ "${PR_MODE:-false}" = "true" ]; then
            log "PR mode enabled, detecting changed tasks using GitHub CLI..."
            readarray -t test_items < <(detect_pr_changes) || {
                error "No tasks to test in PR mode. Check GitHub CLI authentication and PR status."
                exit 1
            }
        else
            warn "No test items provided, attempting to detect changed tasks..."
            readarray -t test_items < <(detect_changed_tasks) || {
                error "No tasks to test. Specify task directories or files explicitly."
                show_help
                exit 1
            }
        fi
    fi
    
    log "Test items: ${test_items[*]}"
    
    if [ "$dry_run" = "true" ]; then
        log "DRY RUN - Would test the following items:"
        for item in "${test_items[@]}"; do
            echo "  - $item"
        done
        return 0
    fi
    
    # Classify tasks by workflow type unless forced
    local workflow_classification
    workflow_classification=$(classify_tasks "${test_items[@]}")
    
    if [ "$verbose" = "true" ]; then
        log "Classification result: $workflow_classification"
    fi
    
    local trusted_artifacts_tasks pvc_tasks
    trusted_artifacts_tasks=$(echo "$workflow_classification" | grep "^TRUSTED_ARTIFACTS:" | cut -d: -f2- | xargs -n1 echo | grep -v "^$" || echo "")
    pvc_tasks=$(echo "$workflow_classification" | grep "^PVC:" | cut -d: -f2- | xargs -n1 echo | grep -v "^$" || echo "")
    
    local test_script="${REPO_ROOT}/.github/scripts/test_tekton_tasks.sh"
    local test_args=()
    
    if [ "$remove_compute_resources" = "true" ]; then
        test_args+=("--remove-compute-resources")
    fi
    
    if [ "$verbose" = "true" ]; then
        set -x
    fi
    
    # Get parallel execution setting  
    local max_parallel="${MAX_PARALLEL:-1}"
    log "Execution mode: $([ "$max_parallel" -eq 1 ] && echo "sequential" || echo "parallel (max: $max_parallel)")"
    
    # Determine test execution approach
    if [ "$max_parallel" -eq 1 ]; then
        # Sequential execution - use original logic
        case "$force_workflow" in
            "trusted-artifacts")
                if [ -n "$trusted_artifacts_tasks" ] || [ -n "$pvc_tasks" ]; then
                    log "Running all tests with Trusted Artifacts workflow (forced)..."
                    if [ ${#test_args[@]} -gt 0 ]; then
                        TEST_ITEMS="${test_items[*]}" \
                        USE_TRUSTED_ARTIFACTS=true \
                        DOCKER_CONFIG_JSON="${DOCKER_CONFIG_JSON:-}" \
                        "$test_script" "${test_args[@]}"
                    else
                        TEST_ITEMS="${test_items[*]}" \
                        USE_TRUSTED_ARTIFACTS=true \
                        DOCKER_CONFIG_JSON="${DOCKER_CONFIG_JSON:-}" \
                        "$test_script"
                    fi
                fi
                ;;
            "pvc")
                if [ -n "$trusted_artifacts_tasks" ] || [ -n "$pvc_tasks" ]; then
                    log "Running all tests with PVC workflow (forced)..."
                    if [ ${#test_args[@]} -gt 0 ]; then
                        TEST_ITEMS="${test_items[*]}" "$test_script" "${test_args[@]}"
                    else
                        TEST_ITEMS="${test_items[*]}" "$test_script"
                    fi
                fi
                ;;
            *)
                # Auto-detect and run appropriate workflow
                if [ -n "$trusted_artifacts_tasks" ]; then
                    log "Running Trusted Artifacts tests..."
                    if [ ${#test_args[@]} -gt 0 ]; then
                        TEST_ITEMS="$trusted_artifacts_tasks" \
                        USE_TRUSTED_ARTIFACTS=true \
                        DOCKER_CONFIG_JSON="${DOCKER_CONFIG_JSON:-}" \
                        "$test_script" "${test_args[@]}"
                    else
                        TEST_ITEMS="$trusted_artifacts_tasks" \
                        USE_TRUSTED_ARTIFACTS=true \
                        DOCKER_CONFIG_JSON="${DOCKER_CONFIG_JSON:-}" \
                        "$test_script"
                    fi
                fi
                
                if [ -n "$pvc_tasks" ]; then
                    log "Running PVC-based tests..."
                    if [ ${#test_args[@]} -gt 0 ]; then
                        TEST_ITEMS="$pvc_tasks" "$test_script" "${test_args[@]}"
                    else
                        TEST_ITEMS="$pvc_tasks" "$test_script"
                    fi
                fi
                ;;
        esac
    else
        # Parallel execution
        run_tests_parallel "$force_workflow" "$trusted_artifacts_tasks" "$pvc_tasks" "$max_parallel" "${test_items[@]}"
    fi
    
    # Validate that all pipeline runs actually succeeded in Kubernetes
    # This addresses infrastructure bugs where tests report FAILED but Kubernetes shows success
    log "Validating pipeline run status in Kubernetes..."
    local validation_failed=false
    
    # Get all recent pipeline runs (from last 10 minutes to catch test runs)
    local recent_prs
    recent_prs=$(kubectl get pipelinerun --sort-by=.metadata.creationTimestamp --no-headers -o custom-columns=":metadata.name,:status.conditions[0].status" | tail -10 || echo "")
    
    if [ -n "$recent_prs" ]; then
        while IFS= read -r pr_line; do
            if [ -n "$pr_line" ]; then
                local pr_name=$(echo "$pr_line" | awk '{print $1}')
                local pr_status=$(echo "$pr_line" | awk '{print $2}')
                
                # Check if this is a test pipeline run and if it failed
                if [[ "$pr_name" =~ ^test- ]]; then
                    if [ "$pr_status" != "True" ] && [ "$pr_status" != "Unknown" ]; then
                        error "Pipeline run $pr_name has status: $pr_status (expected: True)"
                        validation_failed=true
                    else
                        log "✅ Pipeline run $pr_name status: $pr_status"
                    fi
                fi
            fi
        done <<< "$recent_prs"
    fi
    
    if [ "$validation_failed" = "true" ]; then
        error "Pipeline validation failed - some tests actually failed in Kubernetes"
        exit 1
    fi
    
    # Generate test summary
    generate_test_summary
    
    if [ "$cleanup" = "true" ]; then
        log "Cleaning up test resources and results..."
        kubectl delete pipelinerun --all --timeout=60s || warn "Failed to delete some PipelineRuns"
        kubectl delete taskrun --all --timeout=60s || warn "Failed to delete some TaskRuns"
        rm -rf "$RESULTS_DIR" || warn "Failed to remove results directory"
    fi
    
    success "Tests completed successfully!"
}

main() {
    local test_items=()
    local remove_compute_resources=false
    local force_workflow=""
    local dry_run=false
    local cleanup=false
    local verbose=false
    local max_parallel="${MAX_PARALLEL:-1}"
    local pr_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            --remove-compute-resources)
                remove_compute_resources=true
                shift
                ;;
            --trusted-artifacts)
                force_workflow="trusted-artifacts"
                shift
                ;;
            --pvc)
                force_workflow="pvc"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --cleanup)
                cleanup=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --parallel)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    max_parallel="$2"
                    shift 2
                else
                    error "--parallel requires a numeric argument"
                    exit 1
                fi
                ;;
            --pr-mode)
                pr_mode=true
                shift
                ;;
            --*)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                test_items+=("$1")
                shift
                ;;
        esac
    done
    
    export REMOVE_COMPUTE_RESOURCES="$remove_compute_resources"
    export FORCE_WORKFLOW="$force_workflow"
    export DRY_RUN="$dry_run"
    export CLEANUP="$cleanup"
    export VERBOSE="$verbose"
    export MAX_PARALLEL="$max_parallel"
    export PR_MODE="$pr_mode"
    
    check_environment
    setup_results_tracking
    run_tests "${test_items[@]}"
}

main "$@"