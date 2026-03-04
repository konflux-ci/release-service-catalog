#!/usr/bin/env bash
#
# rh-advisories-large-snapshot test script
#
# Stress test for the rh-advisories pipeline using a static pool of 200 pre-built images.
# Uses 2 run-unique UUID tags + 2 static tags per component to force ~400 fresh Pyxis signing ops/run.
#
# USAGE:
#   ./test.sh
#   FRESH_BUILDS_FILE=/path/to/image-list.txt ./test.sh
#
# For general test infrastructure and requirements, see:
#   integration-tests/README.md (common setup, cluster architecture, secrets)
#
# --- Script Directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

FRESH_BUILDS_FILE="${FRESH_BUILDS_FILE:-/tmp/fresh-images-pool-$(date +%s).txt}"

# Image list selection priority:
# 1. FRESH_BUILDS_FILE (explicit override)
# 2. Static pool (default)
if [ -z "${FRESH_BUILDS_FILE:-}" ] || [[ "${FRESH_BUILDS_FILE}" == /tmp/fresh-images-pool-* ]]; then
    FRESH_BUILDS_FILE="${SCRIPT_DIR}/resources/static-image-pool-stable.txt"
fi

if [ ! -f "${FRESH_BUILDS_FILE}" ]; then
    echo "❌ Error: Image list file not found: ${FRESH_BUILDS_FILE}"
    echo "   Provide FRESH_BUILDS_FILE or ensure resources/static-image-pool-stable.txt exists"
    exit 1
fi

echo "  Image list: ${FRESH_BUILDS_FILE}"
echo ""

# --- Export Configuration ---
export FRESH_BUILDS_FILE

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running Large Snapshot Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔧 Configuration:"
echo "  Per-component tag suffix: ${uuid} (from PipelineRun UID / uuid)"
echo ""
echo "ℹ️  Using pre-defined image list (no build/recovery in this run)"
echo ""

# --- Timeout Configuration (in seconds, configurable via environment) ---
# Time to wait for snapshot resource to be persisted
SNAPSHOT_READY_TIMEOUT="${SNAPSHOT_READY_TIMEOUT:-60}"
SNAPSHOT_READY_POLL_INTERVAL="${SNAPSHOT_READY_POLL_INTERVAL:-2}"

# Time to wait for release to start processing
RELEASE_START_TIMEOUT="${RELEASE_START_TIMEOUT:-600}"  # 10 minutes
RELEASE_START_POLL_INTERVAL="${RELEASE_START_POLL_INTERVAL:-5}"

CONSOLE_URL=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}" \
    | sed 's/api/konflux-ui.apps/g' | sed 's/:6443//g')
CONSOLE_URL="${CONSOLE_URL%/}/"

# Explicit allowlist for envsubst — prevents corrupting Ansible vault markers ($ANSIBLE_VAULT...).
# Add new template variables here.
readonly ENVSUBST_ALLOWLIST='$application_name $component_branch $component_git_url $component_name $ec_public_key_ref $managed_namespace $managed_sa_name $originating_tool $release_plan_admission_name $release_plan_name $tenant_namespace $tenant_sa_name $RELEASE_CATALOG_GIT_REVISION $RELEASE_CATALOG_GIT_URL $LARGE_SNAPSHOT_TIMEOUT'

# Cleanup function for temporary directory
cleanup_tmpdir() {
    # Safely handle unset or empty tmpDir variable
    local tmp_path="${tmpDir:-}"

    # Early return if tmpDir was never set
    if [ -z "${tmp_path}" ]; then
        return 0
    fi

    # Validate it's actually a directory before attempting cleanup
    if [ ! -d "${tmp_path}" ]; then
        echo "⚠️  Warning: tmpDir path '${tmp_path}' is not a directory, skipping cleanup" >&2
        return 0
    fi

    # Ensure path is within /tmp to prevent accidental deletion of critical paths
    case "${tmp_path}" in
        /tmp/*)
            # Safe: Path is within /tmp
            ;;
        *)
            echo "❌ Error: tmpDir path '${tmp_path}' is not within /tmp, refusing to delete for safety" >&2
            echo "   Only paths starting with /tmp/ are allowed for automatic cleanup" >&2
            return 1
            ;;
    esac

    # Perform cleanup based on CLEANUP flag
    if [ "${CLEANUP}" == "true" ]; then
        echo "Cleaning up temporary directory: ${tmp_path}" >&2
        rm -rf "${tmp_path}" || {
            echo "⚠️  Warning: Failed to remove temporary directory: ${tmp_path}" >&2
            return 1
        }
    else
        echo "Skipping tmpDir cleanup (--skip-cleanup): ${tmp_path}" >&2
    fi
}

# Generic polling helper with timeout
# Usage: wait_for_condition "description" timeout_seconds poll_interval_seconds condition_function_name [function_args...]
# Returns: 0 on success, 1 on timeout or condition failure
wait_for_condition() {
    local description="$1"
    local timeout="$2"
    local poll_interval="$3"
    local condition_function="$4"

    # Validate required parameters
    : "${description:?description parameter is required}"
    : "${timeout:?timeout parameter is required}"
    : "${poll_interval:?poll_interval parameter is required}"
    : "${condition_function:?condition_function parameter is required}"

    # Validate numeric parameters are positive integers
    if ! [[ "${timeout}" =~ ^[1-9][0-9]*$ ]]; then
        echo "❌ Error: timeout must be a positive integer (got: '${timeout}')" >&2
        return 1
    fi
    if ! [[ "${poll_interval}" =~ ^[1-9][0-9]*$ ]]; then
        echo "❌ Error: poll_interval must be a positive integer (got: '${poll_interval}')" >&2
        return 1
    fi

    # Validate that the condition function exists
    if ! declare -F "${condition_function}" >/dev/null 2>&1; then
        echo "❌ Error: condition function '${condition_function}' does not exist" >&2
        echo "   Available functions can be listed with: declare -F" >&2
        return 1
    fi

    shift 4  # Remove first 4 args, leaving any additional args for the condition function

    echo "Waiting for ${description} (timeout: ${timeout}s)..." >&2
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Use arithmetic comparison for robustness with numeric values
        if (( elapsed >= timeout )); then
            echo "❌ Timeout waiting for ${description} after ${timeout}s" >&2
            return 1
        fi

        # Execute condition function with any additional arguments
        if "$condition_function" "$@"; then
            echo "✅ ${description}" >&2
            return 0
        fi

        sleep "$poll_interval"
    done
}

# Set trap to cleanup tmpDir on exit
trap cleanup_tmpdir EXIT

# Function to create a large snapshot manifest with pre-built components
create_large_snapshot() {
    # Validate required variables
    : "${SUITE_DIR:?SUITE_DIR must be set}"
    : "${tmpDir:?tmpDir must be set}"
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${application_name:?application_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    echo "Creating large snapshot manifest with 200 components..." >&2

    local snapshot_file="${tmpDir}/large-snapshot.yaml"

    "${SUITE_DIR}/utils/generate-large-snapshot.sh" \
        "${large_snapshot_name}" \
        "${application_name}" \
        "${tenant_namespace}" > "${snapshot_file}" || return 1

    echo "✅ Large snapshot manifest created with 200 components" >&2
    echo "${snapshot_file}"
}

# Condition check: Is snapshot created and persisted?
check_snapshot_ready() {
    local snapshot_name="$1"
    local namespace="$2"

    # Validate required parameters
    : "${snapshot_name:?snapshot_name parameter is required}"
    : "${namespace:?namespace parameter is required}"

    [ -n "$(kubectl get snapshot "${snapshot_name}" -n "${namespace}" -o jsonpath='{.metadata.name}' 2>/dev/null)" ]
}

# Function to apply the large snapshot
apply_large_snapshot() {
    # Validate required variables
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${SNAPSHOT_READY_TIMEOUT:?SNAPSHOT_READY_TIMEOUT must be set}"
    : "${SNAPSHOT_READY_POLL_INTERVAL:?SNAPSHOT_READY_POLL_INTERVAL must be set}"

    echo "Applying large snapshot to cluster..." >&2

    # Use pre-generated manifest if available (set by the caller before patching
    # the RPA), otherwise generate it now.
    if [ -z "${LARGE_SNAPSHOT_FILE:-}" ] || [ ! -f "${LARGE_SNAPSHOT_FILE}" ]; then
        LARGE_SNAPSHOT_FILE=$(create_large_snapshot)
        if [ $? -ne 0 ]; then
            echo "❌ Failed to create snapshot manifest" >&2
            return 1
        fi
    fi

    # Apply snapshot to cluster
    kubectl apply -f "${LARGE_SNAPSHOT_FILE}" -n "${tenant_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to apply snapshot to namespace ${tenant_namespace}" >&2
        return 1
    fi

    # Wait for snapshot to be ready using polling helper
    wait_for_condition \
        "snapshot ${large_snapshot_name} to be ready" \
        "$SNAPSHOT_READY_TIMEOUT" \
        "$SNAPSHOT_READY_POLL_INTERVAL" \
        check_snapshot_ready \
        "${large_snapshot_name}" \
        "${tenant_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed waiting for snapshot to be ready" >&2
        return 1
    fi

    echo "✅ Large snapshot applied and ready" >&2
    return 0
}

# Function to create Release CR for large snapshot
create_release_for_large_snapshot() {
    # Validate required variables
    : "${tmpDir:?tmpDir must be set}"
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${originating_tool:?originating_tool must be set}"
    : "${release_plan_name:?release_plan_name must be set}"

    echo "Creating Release CR for large snapshot..." >&2

    local release_file="${tmpDir}/release.yaml"

    cat > "${release_file}" <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${large_snapshot_name}-release
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test.appstudio.openshift.io/large-snapshot: "true"
  annotations:
    # Skip idempotency check to allow re-running test with same snapshot
    # Expected behavior: Release processing proceeds even if snapshot was previously released
    # Rationale: This is a test that uses static pre-built images, not a production release
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  snapshot: ${large_snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    # Apply Release CR to cluster
    kubectl apply -f "${release_file}" -n "${tenant_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to apply Release CR to namespace ${tenant_namespace}" >&2
        return 1
    fi

    echo "✅ Release CR created: ${large_snapshot_name}-release" >&2
    return 0
}

# Function to verify release contents
verify_release_contents() {
    # Validate required variables
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"
    # CONSOLE_URL is intentionally not required: detection may fail when 'oc'
    # is unavailable (see startup block).  URL lines are skipped when empty.

    local release_name="${large_snapshot_name}-release"
    local verification_failed=false

    echo "Verifying Release contents for ${release_name} in namespace ${tenant_namespace}..." >&2

    # Fetch Release JSON
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${tenant_namespace}" -ojson 2>/dev/null || echo "")
    if [ -z "$release_json" ]; then
        echo "❌ Could not retrieve Release JSON for ${release_name} in namespace ${tenant_namespace}" >&2
        echo "   This usually means the Release object does not exist or is not accessible" >&2
        return 1
    fi

    # Check release status
    local succeeded
    succeeded=$(echo "$release_json" | jq -r '.status.conditions[] | select(.type=="Released") | .status' 2>/dev/null || echo "")
    local processing
    processing=$(echo "$release_json" | jq -r '.status.conditions[] | select(.type=="Processing") | .status' 2>/dev/null || echo "")

    echo "Release status:" >&2
    echo "  Succeeded: ${succeeded}" >&2
    echo "  Processing: ${processing}" >&2

    if [ "$succeeded" == "True" ]; then
        echo "✅ Release completed successfully" >&2
    elif [ "$processing" == "True" ]; then
        echo "⚠️  Release is still processing - this is expected for large snapshots" >&2
        echo "   Manual verification may be needed" >&2
    else
        echo "⚠️  Release may have encountered issues - manual verification needed" >&2
        echo "   This is not necessarily a failure for large snapshot tests" >&2
    fi

    # Get PipelineRun
    local pipelinerun
    pipelinerun=$(echo "$release_json" | jq -r '.status.managedProcessing.pipelineRun' 2>/dev/null || echo "")
    
    # Extract just the name part (pipelinerun is stored as "namespace/name")
    local pipelinerun_name="${pipelinerun##*/}"
    
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        [[ -n "${CONSOLE_URL:-}" ]] && \
            echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun_name}" >&2
    fi

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Automated Verification Checks:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # ============================================================================
    # CHECK 0: Critical Task Results (skip_release, mapped)
    # ============================================================================
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "" >&2
        echo "0️⃣  Checking Critical Task Results..." >&2
        
        # Check filter-already-released-advisory-images: skip_release result
        local skip_release
        skip_release=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=filter-already-released-advisory-images" \
            -o jsonpath='{.items[0].status.results[?(@.name=="skip_release")].value}' 2>/dev/null || echo "")
        
        echo "   skip_release: '${skip_release}' (should be 'false' for release to proceed)" >&2
        if [ "${skip_release}" = "false" ]; then
            echo "      ✅ Release will proceed (skip_release=false)" >&2
        elif [ "${skip_release}" = "true" ]; then
            echo "      ⚠️  WARNING: skip_release=true means release tasks will be skipped!" >&2
            verification_failed=true
        else
            echo "      ⚠️  WARNING: skip_release value unclear: '${skip_release}'" >&2
        fi
        
        # Check apply-mapping: mapped result
        local mapped
        mapped=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=apply-mapping" \
            -o jsonpath='{.items[0].status.results[?(@.name=="mapped")].value}' 2>/dev/null || echo "")
        
        echo "   mapped: '${mapped}' (should be 'true' for images to be pushed)" >&2
        if [ "${mapped}" = "true" ]; then
            echo "      ✅ Images have registry mappings (mapped=true)" >&2
        elif [ "${mapped}" = "false" ]; then
            echo "      ⚠️  WARNING: mapped=false means no images will be pushed!" >&2
            verification_failed=true
        else
            echo "      ⚠️  WARNING: mapped value unclear: '${mapped}'" >&2
        fi
    fi

    # ============================================================================
    # CHECK 1: Advisory URL Existence
    # ============================================================================
    echo "" >&2
    echo "1️⃣  Checking Advisory URL..." >&2
    local advisory_url
    advisory_url=$(echo "$release_json" | jq -r '.status.artifacts.advisory.url // ""' 2>/dev/null || echo "")
    local advisory_internal_url
    advisory_internal_url=$(echo "$release_json" | jq -r '.status.artifacts.advisory.internal_url // ""' 2>/dev/null || echo "")

    if [ -n "$advisory_url" ] && [ "$advisory_url" != "null" ]; then
        echo "   ✅ Advisory URL found: ${advisory_url}" >&2
        if [ -n "$advisory_internal_url" ] && [ "$advisory_internal_url" != "null" ]; then
            echo "   ✅ Advisory Internal URL found: ${advisory_internal_url}" >&2
        fi
    else
        echo "   ❌ FAILURE: Advisory URL not found in Release status" >&2
        echo "      Problem: The create-advisory task should populate .status.artifacts.advisory" >&2
        echo "      Current value: '${advisory_url}'" >&2
        echo "      Possible causes:" >&2
        echo "        - create-advisory task failed or was skipped" >&2
        echo "        - Advisory creation timed out" >&2
        echo "        - update-cr-status task failed to update Release CR" >&2
        echo "      How to debug:" >&2
        echo "        kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts}'" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=create-advisory" >&2
        verification_failed=true
    fi

    # ============================================================================
    # CHECK 2: Published Images Count
    # ============================================================================
    echo "" >&2
    echo "2️⃣  Checking Published Images Count..." >&2
    local published_count
    published_count=$(echo "$release_json" | jq -r '.status.artifacts.images | length // 0' 2>/dev/null || echo "0")
    local expected_count=200

    echo "   Expected images: ${expected_count}" >&2
    echo "   Published images: ${published_count}" >&2

    if [ "$published_count" -eq "$expected_count" ]; then
        echo "   ✅ All ${expected_count} images published successfully" >&2
    elif [ "$published_count" -gt 0 ]; then
        local missing_count=$((expected_count - published_count))
        echo "   ❌ FAILURE: Image count mismatch - ${missing_count} images missing" >&2
        echo "      Problem: Expected ${expected_count} images but only ${published_count} were published" >&2
        echo "      Possible causes:" >&2
        echo "        - push-snapshot task failed for some images" >&2
        echo "        - Network issues during image push" >&2
        echo "        - Registry quota or permissions issues" >&2
        echo "        - Some images were filtered out by filter-already-released-advisory-images" >&2
        echo "      How to debug:" >&2
        echo "        # Check which images were published:" >&2
        echo "        kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.images[*]}' | jq -r '.[]'" >&2
        echo "        # Check push-snapshot task logs:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=push-snapshot --sort-by=.metadata.creationTimestamp" >&2
        echo "        # Check if images were filtered:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=filter-already-released-advisory-images -o yaml" >&2
        verification_failed=true
    else
        echo "   ❌ FAILURE: No images found in artifacts.images list" >&2
        echo "      Problem: .status.artifacts.images is empty or missing" >&2
        echo "      Current value: '$(echo "$release_json" | jq -r '.status.artifacts.images // "null"')'" >&2
        echo "      Possible causes:" >&2
        echo "        - push-snapshot task was skipped (check 'when' conditions)" >&2
        echo "        - push-snapshot task failed completely" >&2
        echo "        - apply-mapping returned mapped=false (no registry mappings configured)" >&2
        echo "        - update-cr-status task failed to update Release CR" >&2
        echo "      How to debug:" >&2
        echo "        # Check if push-snapshot ran:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=push-snapshot" >&2
        echo "        # Check apply-mapping results:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=apply-mapping -o jsonpath='{.items[0].status.results}'" >&2
        echo "        # Check full Release status:" >&2
        echo "        kubectl get release ${release_name} -n ${tenant_namespace} -o yaml | grep -A 50 'status:'" >&2
        verification_failed=true
    fi

    # ============================================================================
    # CHECK 3: Task Results Inspection (create-advisory)
    # ============================================================================
    echo "" >&2
    echo "3️⃣  Inspecting Task Results..." >&2
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        # Get create-advisory TaskRun
        local advisory_taskrun
        advisory_taskrun=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=create-advisory" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

        if [ -n "$advisory_taskrun" ]; then
            echo "   TaskRun: ${advisory_taskrun}" >&2
            
            # Check task completion status
            local taskrun_json task_status task_reason task_message
            taskrun_json=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o json 2>/dev/null || echo "{}")
            task_status=$(echo "${taskrun_json}" | jq -r '.status.conditions[] | select(.type=="Succeeded") | .status // ""')
            task_reason=$(echo "${taskrun_json}" | jq -r '.status.conditions[] | select(.type=="Succeeded") | .reason // ""')
            task_message=$(echo "${taskrun_json}" | jq -r '.status.conditions[] | select(.type=="Succeeded") | .message // ""')
            
            if [ "$task_status" == "True" ]; then
                echo "   ✅ create-advisory task succeeded" >&2
            elif [ "$task_status" == "False" ]; then
                echo "   ❌ FAILURE: create-advisory task failed" >&2
                echo "      Problem: Advisory creation task did not complete successfully" >&2
                echo "      Task status: ${task_status}" >&2
                echo "      Reason: ${task_reason}" >&2
                if [ -n "$task_message" ]; then
                    echo "      Message: ${task_message}" >&2
                fi
                echo "      Possible causes:" >&2
                echo "        - Errata API authentication failed" >&2
                echo "        - Advisory creation request was rejected by Errata" >&2
                echo "        - Network connectivity issues to Errata service" >&2
                echo "        - Invalid data keys or missing required fields" >&2
                echo "      How to debug:" >&2
                echo "        # View full task logs:" >&2
                echo "        kubectl logs -n ${managed_namespace} -l tekton.dev/taskRun=${advisory_taskrun} --all-containers" >&2
                echo "        # View task details:" >&2
                echo "        kubectl get taskrun ${advisory_taskrun} -n ${managed_namespace} -o yaml" >&2
                verification_failed=true
            else
                echo "   ⚠️  WARNING: create-advisory task status unclear: ${task_status}" >&2
                echo "      Reason: ${task_reason}" >&2
                echo "      This may indicate the task is still running or was skipped" >&2
            fi

            local task_advisory_url task_advisory_internal_url
            task_advisory_url=$(echo "${taskrun_json}" | jq -r '.status.results[] | select(.name=="advisory_url") | .value // ""')
            task_advisory_internal_url=$(echo "${taskrun_json}" | jq -r '.status.results[] | select(.name=="advisory_internal_url") | .value // ""')

            if [ -n "$task_advisory_url" ] && [ "$task_advisory_url" != "null" ]; then
                echo "   ✅ Advisory URL from task: ${task_advisory_url}" >&2
            else
                if [ "$task_status" == "True" ]; then
                    echo "   ⚠️  WARNING: Advisory URL not found in task results despite task success" >&2
                    echo "      This may indicate a bug in the create-advisory task" >&2
                fi
            fi

            if [ -n "$task_advisory_internal_url" ] && [ "$task_advisory_internal_url" != "null" ]; then
                echo "   ✅ Advisory Internal URL from task: ${task_advisory_internal_url}" >&2
            fi
        else
            echo "   ⚠️  WARNING: create-advisory TaskRun not found" >&2
            echo "      Problem: Cannot find TaskRun with label tekton.dev/pipelineTask=create-advisory" >&2
            echo "      Possible causes:" >&2
            echo "        - Task was skipped due to 'when' conditions (e.g., skip_release=true)" >&2
            echo "        - Task hasn't started yet (still pending)" >&2
            echo "        - Task name mismatch or label issues" >&2
            echo "      How to debug:" >&2
            echo "        # List all tasks in this PipelineRun:" >&2
            echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineRun=${pipelinerun_name}" >&2
            echo "        # Check PipelineRun status:" >&2
            echo "        kubectl get pipelinerun ${pipelinerun_name} -n ${managed_namespace} -o yaml | grep -A 20 'status:'" >&2
        fi
    else
        echo "   ⚠️  WARNING: PipelineRun not available, skipping task inspection" >&2
        echo "      Problem: .status.managedProcessing.pipelineRun is empty or null" >&2
        echo "      This usually means the Release hasn't started processing yet" >&2
    fi

    # ============================================================================
    # CHECK 4: Task Execution Debug Info
    # ============================================================================
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "" >&2
        echo "4️⃣  Task Execution Summary..." >&2
        
        # List all TaskRuns in the PipelineRun
        local all_taskruns
        all_taskruns=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name}" \
            -o jsonpath='{range .items[*]}{.metadata.labels.tekton\.dev/pipelineTask}{"\t"}{.status.conditions[?(@.type=="Succeeded")].status}{"\n"}{end}' 2>/dev/null || echo "")
        
        if [ -n "$all_taskruns" ]; then
            echo "   Tasks executed:" >&2
            local task_count=0
            local succeeded_count=0
            local failed_count=0
            
            while IFS=$'\t' read -r task_name task_status; do
                [ -z "$task_name" ] && continue
                task_count=$((task_count + 1))
                
                case "$task_status" in
                    "True")
                        echo "      ✅ ${task_name}" >&2
                        succeeded_count=$((succeeded_count + 1))
                        ;;
                    "False")
                        echo "      ❌ ${task_name}" >&2
                        failed_count=$((failed_count + 1))
                        ;;
                    "Unknown")
                        echo "      🔄 ${task_name} (running)" >&2
                        ;;
                    *)
                        echo "      ⏳ ${task_name} (status: ${task_status})" >&2
                        ;;
                esac
            done <<< "$all_taskruns"
            
            echo "   Total tasks: ${task_count} (✅ ${succeeded_count} succeeded, ❌ ${failed_count} failed)" >&2
        else
            echo "   ⚠️  No TaskRuns found for PipelineRun ${pipelinerun_name}" >&2
        fi
    fi

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Verification Summary:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # Summary
    if [ "$verification_failed" == "true" ]; then
        echo "" >&2
        echo "❌ VERIFICATION FAILED: One or more automated checks found issues" >&2
        echo "" >&2
        echo "Next steps:" >&2
        echo "  1. Review the failure messages above for specific issues" >&2
        echo "  2. Run the suggested debug commands to investigate" >&2
        echo "  3. Check PipelineRun logs for detailed error messages:" >&2
        if [[ -n "${CONSOLE_URL:-}" ]]; then
            echo "     ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun_name}" >&2
        else
            echo "     kubectl logs -n ${managed_namespace} -l tekton.dev/pipelineRun=${pipelinerun_name}" >&2
        fi
        echo "  4. Examine the Release CR status:" >&2
        echo "     kubectl get release ${release_name} -n ${tenant_namespace} -o yaml" >&2
        echo "" >&2
        # Write a brief summary to a well-known path so the pipeline can surface it
        # as a Tekton step result (always visible regardless of log truncation).
        {
            echo "FAILED"
            echo "Release: ${release_name:-unknown} | PipelineRun: ${pipelinerun_name:-unknown}"
            echo "One or more verification checks failed — see step log for details."
        } > /tmp/verification-summary.txt
        return 1
    else
        echo "" >&2
        echo "✅ SUCCESS: All automated verification checks passed" >&2
        echo "" >&2
        echo "What was verified:" >&2
        echo "  ✅ Advisory URL exists and is accessible in Release status" >&2
        echo "  ✅ All ${expected_count} images were successfully published" >&2
        echo "  ✅ create-advisory task completed successfully" >&2
        echo "" >&2
        echo "⚠️  Note: For large snapshots (200 components), additional manual verification" >&2
        echo "   is recommended to ensure advisory content quality and completeness." >&2
        echo "" >&2
        echo "Manual verification commands:" >&2
        echo "  # View advisory:" >&2
        echo "  echo ${advisory_url}" >&2
        echo "  # Count published images:" >&2
        echo "  kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.images}' | jq 'length'" >&2
        echo "  # View all published images:" >&2
        echo "  kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.images[*]}' | jq" >&2
        echo "" >&2
        # Write a brief summary to a well-known path so the pipeline can surface it
        # as a Tekton step result (always visible regardless of log truncation).
        {
            echo "PASSED"
            echo "Release: ${release_name:-unknown} | PipelineRun: ${pipelinerun_name:-unknown}"
            echo "Advisory: ${advisory_url:-N/A} | Images published: ${published_count:-0}/${expected_count:-0}"
        } > /tmp/verification-summary.txt
        return 0
    fi
}

# Condition check: Is release processing?
check_release_processing() {
    local release_name="$1"
    local namespace="$2"

    # Validate required parameters
    : "${release_name:?release_name parameter is required}"
    : "${namespace:?namespace parameter is required}"

    # Check if release has started processing by looking for managedProcessing.pipelineRun
    local pipelinerun
    pipelinerun=$(kubectl get release "${release_name}" -n "${namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || echo "")
    [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]
}

# Function to wait for release to start processing
wait_for_release_to_start() {
    # Validate required variables
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"
    : "${RELEASE_START_TIMEOUT:?RELEASE_START_TIMEOUT must be set}"
    : "${RELEASE_START_POLL_INTERVAL:?RELEASE_START_POLL_INTERVAL must be set}"
    # CONSOLE_URL is intentionally not required: detection may fail when 'oc'
    # is unavailable (see startup block).  URL lines are skipped when empty.

    local release_name="${large_snapshot_name}-release"

    echo "  Release: ${release_name}" >&2

    # Wait for release Processing condition using polling helper
    wait_for_condition \
        "release ${release_name} to start processing" \
        "$RELEASE_START_TIMEOUT" \
        "$RELEASE_START_POLL_INTERVAL" \
        check_release_processing \
        "${release_name}" \
        "${tenant_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Release did not start processing within ${RELEASE_START_TIMEOUT}s" >&2
        return 1
    fi

    # Extract and display PipelineRun information
    local pipelinerun
    pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || echo "")
    
    # Extract just the name part (pipelinerun is stored as "namespace/name")
    local pipelinerun_name="${pipelinerun##*/}"

    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        [[ -n "${CONSOLE_URL:-}" ]] && \
            echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun_name}" >&2

        export RELEASE_PIPELINERUN="${pipelinerun}"
    fi

    echo "✅ Release started processing" >&2
    return 0
}

# Override: GitHub repo creation
create_github_repository() {
    echo "Creating minimal GitHub repository for test metadata..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"
}

# Override: Skip component source patching
patch_component_source() {
    echo "⏩ Skipping component source patch - no builds needed"
}

# Override: Skip component initialization
wait_for_component_initialization() {
    echo "⏩ Skipping component initialization - using pre-built images"
}

# Override: Skip pre-merge patching
patch_component_source_before_merge() {
    echo "⏩ Skipping component source patch - no builds needed"
}

# Override: Skip PR merge
merge_github_pr() {
    echo "⏩ Skipping PR merge - using pre-built images"
}

# Override: Skip PLR wait
wait_for_plr_to_appear() {
    echo "⏩ Skipping PLR wait - no builds triggered"
}

# Override: Skip PLR completion
wait_for_plr_to_complete() {
    echo "⏩ Skipping PLR completion - no builds needed"
}

# Override: Cleanup with old release cleanup
cleanup_resources() {
    local err=${1:-0}
    local line=${2:-"N/A"}
    local command=${3:-"N/A"}

    if [ "$err" -ne 0 ] ; then
        echo "$0: ERROR: Command '$command' failed at line $line - exited with status $err"
    fi

    if [ "${CLEANUP}" == "true" ]; then
        echo "Performing cleanup..."
        set +eo pipefail

        # Delete the GitHub repository created by create_github_repository().
        # Mirrors the behavior of the shared cleanup_resources in test-functions.sh.
        if [ -n "${component_repo_name:-}" ]; then
            echo "🗑️  Deleting GitHub repository ${component_repo_name} ..."
            "${SUITE_DIR}/../scripts/delete-repository.sh" "${component_repo_name}" || \
                echo "   ⚠ Failed to delete GitHub repository ${component_repo_name}" >&2
        fi

        # Clean up releases created by this test (using originating-tool label)
        echo "🗑️  Cleaning up test releases (originating-tool=${originating_tool:-rh-advisories-large-snapshot-test})..."
        local old_releases
        old_releases=$(kubectl get release -n "${tenant_namespace:-dev-release-team-tenant}" \
            -l "originating-tool=${originating_tool:-rh-advisories-large-snapshot-test}" \
            --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        
        if [ -n "${old_releases}" ]; then
            local count
            count=$(echo "${old_releases}" | wc -l)
            echo "   Found ${count} test releases to clean up"
            
            while IFS= read -r release; do
                if kubectl delete release "${release}" -n "${tenant_namespace:-dev-release-team-tenant}" 2>/dev/null; then
                    echo "   ✓ Deleted ${release}"
                else
                    echo "   ⚠ Failed to delete ${release}"
                fi
            done <<< "${old_releases}"
        else
            echo "   ✓ No test releases found"
        fi

        # Standard cleanup
        if [ -n "$tmpDir" ] && [ -d "$tmpDir" ]; then
            echo "Deleting test resources..."
            if [ -f "$tmpDir/tenant-resources.yaml" ]; then
                # Intentionally avoid deleting Component/Application during cleanup.
                # Only remove supporting tenant resources by label.
                kubectl delete rolebinding,serviceaccount,releaseplan \
                    -n "${tenant_namespace:-dev-release-team-tenant}" \
                    -l "originating-tool=${originating_tool:-rh-advisories-large-snapshot-test}" \
                    --ignore-not-found=true 2>/dev/null || true
            fi
            if [ -f "$tmpDir/managed-resources.yaml" ]; then
                kubectl delete -f "$tmpDir/managed-resources.yaml" 2>/dev/null || true
            fi
            
            rm -rf "${tmpDir}" || echo "   ⚠ Failed to remove tmpDir"
        fi
    else
        echo "Skipping cleanup as per --skip-cleanup flag."
    fi

    echo "Killing any child processes..."
    pkill -e -P $$ 2>/dev/null || true

    if [ "$err" -ne 0 ]; then
        exit "$err"
    fi
}

# Helper: Build kustomize resources, substitute vars, and apply to cluster
# Usage: apply_kustomize_resources "description" "kustomize_dir" "output_file" "namespace"
# Example: apply_kustomize_resources "tenant resources" "${SUITE_DIR}/resources/tenant" "${tmpDir}/tenant.yaml" "${tenant_namespace}"
apply_kustomize_resources() {
    local description="$1"
    local kustomize_dir="$2"
    local output_file="$3"
    local namespace="$4"

    # Validate required parameters
    : "${description:?description parameter is required}"
    : "${kustomize_dir:?kustomize_dir parameter is required}"
    : "${output_file:?output_file parameter is required}"
    : "${namespace:?namespace parameter is required}"

    echo "Building ${description}..." >&2

    # Build with kustomize and substitute environment variables
    # Use explicit allowlist (ENVSUBST_ALLOWLIST) to prevent corrupting Ansible vault secrets
    kustomize build "${kustomize_dir}" | \
        envsubst "${ENVSUBST_ALLOWLIST}" \
        > "${output_file}" || {
        log_error "Failed to build ${description}"
        return 1
    }


    # Apply to cluster with explicit namespace and error handling
    kubectl apply -f "${output_file}" -n "${namespace}" || {
        log_error "Failed to apply ${description} to namespace ${namespace}"
        return 1
    }

    echo "✅ ${description} applied to ${namespace}" >&2
}

# Function to prepare signing ConfigMap override (Feature #2: Signing Key Rotation)
# Function to patch RPA with actual component names from snapshot
# The apply-mapping task does NOT support wildcard "*" matching
patch_rpa_with_snapshot_components() {
    # Validate required variables
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"
    : "${release_plan_admission_name:?release_plan_admission_name must be set}"
    
    echo "Generating component mapping from snapshot..." >&2

    # Prefer the local manifest file (set by apply_large_snapshot) so we can
    # patch the RPA before the snapshot is applied to the cluster.  This
    # prevents the auto-release from firing with the placeholder "name: *"
    # component entry, which would cause the release-service controller to
    # garbage-collect the RPA.
    local components
    if [ -n "${LARGE_SNAPSHOT_FILE:-}" ] && [ -f "${LARGE_SNAPSHOT_FILE}" ]; then
        components=$(yq e '.spec.components[].name' "${LARGE_SNAPSHOT_FILE}" 2>/dev/null)
    fi
    if [ -z "${components:-}" ]; then
        components=$(kubectl get snapshot "${large_snapshot_name}" -n "${tenant_namespace}" \
            -o jsonpath='{range .spec.components[*]}{.name}{"\n"}{end}')
    fi

    if [ -z "${components}" ]; then
        echo "❌ No components found in snapshot ${large_snapshot_name}" >&2
        return 1
    fi
    
    local component_count
    component_count=$(echo "${components}" | wc -l)
    echo "  Found ${component_count} components in snapshot" >&2
    
    # Derive the per-run unique suffix for tags.
    # Prefer an explicit caller override, then the suite uuid (first 8 chars of the
    # PipelineRun UID), then a timestamp fallback for direct local runs.
    local _run_suffix="${uuid:-$(date +%Y%m%d-%H%M%S)}"

    # Build per-component mapping JSON.
    # Each component gets its own tags that embed its name, so no two components
    # ever push to the same (repository_url, tag) pair.
    # Tag layout per component (4 tags × N components = N×4 signing operations):
    #   <name>-<run_suffix>         — run-unique (1st), forces Pyxis to re-sign every run
    #   <name>-v1.0.<run_suffix>    — run-unique (2nd), doubles fresh signing ops vs. one uuid tag
    #   <name>-v1.0                 \
    #   <name>-stable                > static tags, Pyxis-idempotent after first run
    #
    # Using 2 uuid tags + 2 static tags = 400 fresh signing ops per run (200 components).
    #
    # Use a local loop variable (_cn) to avoid shadowing the suite-global
    # component_name exported by test.env (used for per-run resource naming
    # in cleanup and elsewhere).
    local mapping_json='[]'
    local _cn
    while IFS= read -r _cn; do
        [ -z "${_cn}" ] && continue
        local component_entry
        component_entry=$(jq -n \
            --arg name "${_cn}" \
            --arg t0 "${_cn}-${_run_suffix}" \
            --arg t1 "${_cn}-v1.0.${_run_suffix}" \
            --arg t2 "${_cn}-v1.0" \
            --arg t3 "${_cn}-stable" \
            '{
                "name": $name,
                "repositories": [{
                    "url": "quay.io/redhat-pending/rhtap----rh-advisories-component",
                    "tags": [$t0, $t1, $t2, $t3]
                }]
            }')
        mapping_json=$(echo "${mapping_json}" | jq --argjson entry "${component_entry}" '. += [$entry]')
    done <<< "${components}"

    echo "  Generated per-component mapping for ${component_count} components" >&2
    echo "  Run suffix: ${_run_suffix}" >&2

    # Build the merge-patch JSON.
    # We patch only spec.data.mapping.components — NOT spec.data.mapping.defaults.
    # Kubernetes merge-patch replaces the entire nested object at the specified key,
    # so including "defaults: { tags: [] }" would wipe out defaults.pushSourceContainer
    # and defaults.repositories from the live RPA.
    # Per-component repositories[].tags already override defaults.tags in apply-mapping,
    # so clearing defaults is not needed for collision prevention.
    local patch_json
    patch_json=$(jq -n \
        --argjson components "${mapping_json}" \
        '{
            spec: {
                data: {
                    mapping: { components: $components }
                }
            }
        }')

    echo "  Patching ReleasePlanAdmission: ${release_plan_admission_name}" >&2
    if ! kubectl patch releaseplanadmission "${release_plan_admission_name}" \
            -n "${managed_namespace}" \
            --type merge \
            -p "${patch_json}"; then
        echo "❌ Failed to patch ReleasePlanAdmission" >&2
        return 1
    fi

    # ── Post-patch validation ─────────────────────────────────────────────────
    # Verify that no two components share a (repository_url, tag) pair.
    # Duplicate pairs would silently overwrite images at push time.
    local dup_count
    dup_count=$(kubectl get releaseplanadmission "${release_plan_admission_name}" \
        -n "${managed_namespace}" \
        -o json 2>/dev/null \
        | jq '
            [.spec.data.mapping.components[]
                | .repositories[]
                | (.url) as $url
                | .tags[]?
                | "\($url):\(.)"]
            | group_by(.)
            | map(select(length > 1))
            | length' 2>/dev/null || echo "0")

    if [ "${dup_count:-0}" -gt 0 ]; then
        echo "❌ Validation failed: ${dup_count} duplicate (repository, tag) pair(s) detected in RPA mapping" >&2
        echo "   This would cause components to overwrite each other at push time." >&2
        kubectl get releaseplanadmission "${release_plan_admission_name}" \
            -n "${managed_namespace}" \
            -o jsonpath='{.spec.data.mapping.components[:3]}' 2>/dev/null \
            | jq '.' >&2 || true
        return 1
    fi

    echo "✅ ReleasePlanAdmission patched: ${component_count} components, 4 unique tags each, no collisions" >&2
    return 0
}

# Override: Resource creation with large snapshot
create_kubernetes_resources() {
    # Validate required variables
    : "${SUITE_DIR:?SUITE_DIR must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"

    echo "Creating Kubernetes resources with large snapshot..." >&2

    # Decrypt vault secrets first (creates resources/*/secrets/ directories)
    decrypt_secrets "${SUITE_DIR}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to decrypt secrets" >&2
        return 1
    fi

    # Create temp directory for resources (global for cleanup trap)
    tmpDir=$(mktemp -d)
    if [ $? -ne 0 ] || [ -z "${tmpDir}" ]; then
        echo "❌ Failed to create temporary directory" >&2
        return 1
    fi
    echo "Using temporary directory: ${tmpDir}" >&2

    # Build and apply tenant resources (Application, Component, etc.)
    apply_kustomize_resources \
        "tenant resources" \
        "${SUITE_DIR}/resources/tenant" \
        "${tmpDir}/tenant-resources.yaml" \
        "${tenant_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create tenant resources" >&2
        return 1
    fi

    # Validate catalog variables before building managed resources (required for RPA)
    : "${RELEASE_CATALOG_GIT_URL:?RELEASE_CATALOG_GIT_URL must be set (required for ReleasePlanAdmission)}"
    : "${RELEASE_CATALOG_GIT_REVISION:?RELEASE_CATALOG_GIT_REVISION must be set (required for ReleasePlanAdmission)}"

    # Pool images are already signed by Tekton Chains — use its public key for EC policy.
    export ec_public_key_ref="k8s://openshift-pipelines/public-key"
    echo "  EC public key ref: ${ec_public_key_ref}" >&2

    # Build and apply managed resources (RPA, EC Policy, etc.)
    apply_kustomize_resources \
        "managed resources" \
        "${SUITE_DIR}/resources/managed" \
        "${tmpDir}/managed-resources.yaml" \
        "${managed_namespace}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create managed resources" >&2
        return 1
    fi


    # Generate snapshot manifest and patch the RPA before applying the snapshot.
    # Order matters: the RP has auto-release=true, so the release-service fires
    # a Release the moment the snapshot lands on the cluster.  If the RPA still
    # carries the placeholder "name: *" at that point, apply-mapping will reject
    # the release and the controller will garbage-collect the RPA.  Generating
    # the manifest first (sets LARGE_SNAPSHOT_FILE) lets patch_rpa_with_snapshot_components
    # read component names from the local file, then apply_large_snapshot uploads
    # the snapshot with an already-correct RPA in place.
    echo "Generating snapshot manifest..." >&2
    LARGE_SNAPSHOT_FILE=$(create_large_snapshot)
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create snapshot manifest" >&2
        return 1
    fi

    echo "Patching ReleasePlanAdmission with snapshot component mappings..." >&2
    patch_rpa_with_snapshot_components
    if [ $? -ne 0 ]; then
        echo "❌ Failed to patch RPA with component mappings" >&2
        return 1
    fi

    # Now apply the snapshot — RPA is already correct, no race window.
    apply_large_snapshot
    if [ $? -ne 0 ]; then
        echo "❌ Failed to apply large snapshot" >&2
        return 1
    fi

    # Create a release for the snapshot
    create_release_for_large_snapshot
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create release for large snapshot" >&2
        return 1
    fi

    echo "✅ All Kubernetes resources created successfully" >&2
    return 0
}

# Override: Wait for releases
# Capture a compact managed-pipeline failure summary into /tmp/generate-snapshot-error.txt
# so it surfaces in the test-report FAILURE_CONTEXT result.
# Called after wait-for-release.sh exits non-zero.
diagnose_managed_pipeline_failure() {
    local release_name="${large_snapshot_name}-release"

    local pipelinerun
    pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || true)
    local pipelinerun_name="${pipelinerun##*/}"
    [ -z "${pipelinerun_name}" ] || [ "${pipelinerun_name}" = "null" ] && return 0

    # Collect all failed taskruns for this pipelinerun.
    local failed_rows
    failed_rows=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${pipelinerun_name}" \
        -o json 2>/dev/null \
        | jq -r '.items[]
            | select(.status.conditions[0].status == "False")
            | [
                .metadata.labels["tekton.dev/pipelineTask"],
                .metadata.name,
                .status.podName,
                .status.conditions[0].message
              ] | @tsv') || true

    [ -z "${failed_rows}" ] && return 0

    {
        printf 'Managed pipeline failed\n'
        printf '  PipelineRun: %s\n' "${pipelinerun_name}"
        while IFS=$'\t' read -r task_name taskrun_name pod_name condition_msg; do
            printf '\n  Failed task : %s\n' "${task_name}"
            printf '  TaskRun     : %s\n' "${taskrun_name}"
            printf '  Condition   : %s\n' "${condition_msg}"
            # Grab the last few error lines from the pod log to show the actual error.
            if [ -n "${pod_name}" ] && [ "${pod_name}" != "null" ]; then
                local log_errors
                log_errors=$(kubectl logs "${pod_name}" -n "${managed_namespace}" \
                    --all-containers 2>/dev/null \
                    | grep -iE 'fatal|error|FAILED|403|404|Forbidden|Not Found' \
                    | tail -5 || true)
                if [ -n "${log_errors}" ]; then
                    printf '  Error lines :\n'
                    while IFS= read -r line; do
                        printf '    %s\n' "${line}"
                    done <<< "${log_errors}"
                fi
            fi
        done <<< "${failed_rows}"
    } > /tmp/generate-snapshot-error.txt

    echo "🔍 Managed pipeline failure context captured → test-report will show details" >&2
}

wait_for_releases() {
    # Validate required variables
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"

    local release_name="${large_snapshot_name}-release"

    # Add labels to the release CR for cleanup tracking
    # - originating-tool: identifies which test suite created it (for cleanup)
    # - test-run-uuid: unique ID from test.env (supports concurrent test runs)
    kubectl patch release "${release_name}" -n "${tenant_namespace}" \
      --type merge \
      -p "{\"metadata\":{\"labels\":{\"originating-tool\":\"${originating_tool}\",\"test-run-uuid\":\"${uuid}\"}}}"

    echo "Waiting for release to start processing..." >&2
    wait_for_release_to_start || log_error "Failed to wait for release to start"

    # Export variables expected by verify_release_contents
    export RELEASE_NAME="${release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    export RELEASE_NAMES="${RELEASE_NAME}"

    echo "Waiting for release pipeline to complete (this may take up to 2h for large snapshots)..." >&2
    if ! "${SUITE_DIR}/../scripts/wait-for-release.sh"; then
        diagnose_managed_pipeline_failure
        return 1
    fi
}

echo "✅ Large snapshot test functions loaded"
