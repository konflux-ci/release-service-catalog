#!/usr/bin/env bash
#
# rh-advisories-large-snapshot test script
#
# LARGE SNAPSHOT TEST SPECIFICS:
# - Tests rh-advisories pipeline with ~200 pre-built components
# - Expected duration: 4-8 hours (not a failure)
# - Skips: Component builds, idempotency checks
# - Uses: Staging Pyxis (stage) and staging signing (staging-redhatbeta2)
# - Trigger: Comment `/test-large-snapshot` on PRs (manual only)
#
# For general test infrastructure and requirements, see:
#   integration-tests/README.md (common setup, cluster architecture, secrets)
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# --- Timeout Configuration (in seconds, configurable via environment) ---
# Time to wait for snapshot resource to be persisted
SNAPSHOT_READY_TIMEOUT="${SNAPSHOT_READY_TIMEOUT:-60}"
SNAPSHOT_READY_POLL_INTERVAL="${SNAPSHOT_READY_POLL_INTERVAL:-2}"

# Time to wait for release to start processing
RELEASE_START_TIMEOUT="${RELEASE_START_TIMEOUT:-600}"  # 10 minutes
RELEASE_START_POLL_INTERVAL="${RELEASE_START_POLL_INTERVAL:-5}"

# Get OpenShift console URL from cluster (dynamic detection)
# Priority: 1. CONSOLE_URL env var, 2. oc whoami --show-console, 3. PaC ConfigMap
# Consistent with other e2e tests - no hardcoded fallback URLs
if [ -z "${CONSOLE_URL:-}" ]; then
    # Try to get console URL dynamically from current cluster context
    # This ensures we get the correct URL for whatever cluster we're actually connected to
    dynamic_console_url=""
    
    if command -v oc &> /dev/null; then
        dynamic_console_url=$(oc whoami --show-console 2>/dev/null || echo "")
    fi
    
    # Validate that we got a URL (must start with http:// or https://)
    if [[ "${dynamic_console_url}" =~ ^https?:// ]]; then
        CONSOLE_URL="${dynamic_console_url}"
        echo "📍 Using console URL from cluster (oc whoami): ${CONSOLE_URL}" >&2
    else
        # Fall back to PaC ConfigMap if oc command failed or not available
        pac_console_url=$(kubectl get cm/pipelines-as-code -n openshift-pipelines -ojson 2>/dev/null | jq -r '.data."custom-console-url" // empty' 2>/dev/null || echo "")

        # Validate that we got a URL (must start with http:// or https://)
        if [[ "${pac_console_url}" =~ ^https?:// ]]; then
            CONSOLE_URL="${pac_console_url}"
            echo "📍 Using console URL from PaC ConfigMap: ${CONSOLE_URL}" >&2
        else
            # Could not detect console URL - URLs in output may be incomplete
            CONSOLE_URL=""
            echo "⚠️  WARNING: Could not detect console URL dynamically" >&2
            echo "   PipelineRun URLs in output may be incomplete" >&2
            echo "   To fix: Export CONSOLE_URL or ensure 'oc' CLI is available" >&2
        fi
    fi
else
    echo "📍 Using console URL from environment variable: ${CONSOLE_URL}" >&2
fi

# Ensure CONSOLE_URL has trailing slash for URL construction
[[ "${CONSOLE_URL}" != */ ]] && CONSOLE_URL="${CONSOLE_URL}/"

# --- envsubst Variable Allowlist ---
# IMPORTANT: Explicit allowlist for envsubst to prevent corrupting Ansible vault secrets
# Without allowlist, envsubst would replace ANY $VAR including $ANSIBLE_VAULT markers
# Only variables in this list will be substituted in kustomize templates
# 
# Variable categories:
#   - Test identity: application_name, component_name, originating_tool
#   - Git/source: component_branch, component_git_url
#   - Namespaces: tenant_namespace, managed_namespace
#   - Service accounts: tenant_sa_name, managed_sa_name
#   - Release config: release_plan_name, release_plan_admission_name
#   - Catalog references: RELEASE_CATALOG_GIT_URL, RELEASE_CATALOG_GIT_REVISION
#   - Timeout config: LARGE_SNAPSHOT_TIMEOUT
#   - Note: PYXIS_SERVER and SIGNING_ENV are hardcoded in test.sh (not interpolated)
#
# When adding new variables:
#   1. Ensure they don't conflict with Ansible vault syntax ($ANSIBLE_VAULT)
#   2. Add them to this list
#   3. Update the comment above with the variable category
#   4. Document in test.env if needed
readonly ENVSUBST_ALLOWLIST='$application_name $component_branch $component_git_url $component_name $managed_namespace $managed_sa_name $originating_tool $release_plan_admission_name $release_plan_name $tenant_namespace $tenant_sa_name $RELEASE_CATALOG_GIT_REVISION $RELEASE_CATALOG_GIT_URL $LARGE_SNAPSHOT_TIMEOUT'

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

    # Security: Ensure path is within /tmp to prevent accidental deletion of critical paths
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
# Example: wait_for_condition "resource to be ready" 60 2 check_resource_ready "my-resource" "default"
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
        # This is safe - we're calling a function by name, not eval'ing arbitrary strings
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
    : "${LARGE_SNAPSHOT_COMPONENT_COUNT:?LARGE_SNAPSHOT_COMPONENT_COUNT must be set}"

    echo "Creating large snapshot manifest with ${LARGE_SNAPSHOT_COMPONENT_COUNT} components..." >&2

    # Extract PR container image from SNAPSHOT env var (has valid Konflux signatures)
    local pr_container_image=""
    if [ -n "${SNAPSHOT:-}" ]; then
        pr_container_image=$(jq -r '.components[0].containerImage // ""' <<< "${SNAPSHOT}")
        if [ -n "${pr_container_image}" ]; then
            echo "Using PR container image from SNAPSHOT (signed by Konflux build)" >&2
            echo "  Image (original): ${pr_container_image}" >&2
            
            # Convert tag to digest if needed (release pipeline requires @sha256: format)
            if [[ ! "${pr_container_image}" =~ @sha256: ]]; then
                echo "  Converting tag to digest..." >&2
                local image_digest
                image_digest=$(skopeo inspect --no-tags "docker://${pr_container_image}" 2>/dev/null | jq -r '.Digest // ""')
                if [ -n "${image_digest}" ]; then
                    # Extract repo without tag/digest
                    local image_repo="${pr_container_image%:*}"
                    image_repo="${image_repo%@*}"
                    pr_container_image="${image_repo}@${image_digest}"
                    echo "  Image (digest): ${pr_container_image}" >&2
                else
                    echo "  ⚠️  Failed to resolve digest, using original" >&2
                fi
            fi
        fi
    fi

    local snapshot_file="${tmpDir}/large-snapshot.yaml"

    "${SUITE_DIR}/utils/generate-large-snapshot.sh" \
        "${large_snapshot_name}" \
        "${application_name}" \
        "${tenant_namespace}" \
        "${LARGE_SNAPSHOT_COMPONENT_COUNT}" \
        "${pr_container_image}" > "${snapshot_file}" || return 1

    echo "✅ Large snapshot manifest created with ${LARGE_SNAPSHOT_COMPONENT_COUNT} components" >&2
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

    # Create snapshot manifest
    local snapshot_file
    snapshot_file=$(create_large_snapshot)
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create snapshot manifest" >&2
        return 1
    fi

    # Apply snapshot to cluster
    kubectl apply -f "${snapshot_file}" -n "${tenant_namespace}"
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
    : "${CONSOLE_URL:?CONSOLE_URL must be set}"

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
    # Extract just the name (remove namespace prefix if present) for label queries
    local pipelinerun_name="${pipelinerun##*/}"
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun}" >&2
    fi

    # ============================================================================
    # DEBUG: Check task results before verifying Release status
    # ============================================================================
    echo "" >&2
    echo "🔍 DEBUG: Checking task results that control when conditions..." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        # Check filter-already-released-advisory-images results
        echo "1️⃣  filter-already-released-advisory-images task:" >&2
        local skip_release
        skip_release=$(kubectl get taskrun -n "${managed_namespace}" \
            -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask=filter-already-released-advisory-images \
            -o jsonpath='{.items[0].status.results[?(@.name=="skip_release")].value}' 2>/dev/null || echo "NOT_FOUND")
        echo "   skip_release = '${skip_release}'" >&2
        if [ "${skip_release}" == "true" ]; then
            echo "   ⚠️  WARNING: skip_release=true causes create-advisory and update-cr-status to be SKIPPED!" >&2
            echo "   This explains why advisory URL and publishedImages are empty." >&2
        elif [ "${skip_release}" == "false" ]; then
            echo "   ✅ skip_release=false (tasks should run normally)" >&2
        else
            echo "   ❌ ERROR: Could not read skip_release result!" >&2
        fi
        
        # Check apply-mapping results
        echo "" >&2
        echo "2️⃣  apply-mapping task:" >&2
        local mapped
        mapped=$(kubectl get taskrun -n "${managed_namespace}" \
            -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask=apply-mapping \
            -o jsonpath='{.items[0].status.results[?(@.name=="mapped")].value}' 2>/dev/null || echo "NOT_FOUND")
        echo "   mapped = '${mapped}'" >&2
        if [ "${mapped}" == "false" ]; then
            echo "   ⚠️  WARNING: mapped=false causes push-snapshot to be SKIPPED!" >&2
        elif [ "${mapped}" == "true" ]; then
            echo "   ✅ mapped=true (push-snapshot should run)" >&2
        else
            echo "   ❌ ERROR: Could not read mapped result!" >&2
        fi
        
        # List all task execution status
        echo "" >&2
        echo "3️⃣  Critical task execution status:" >&2
        for task in filter-already-released-advisory-images apply-mapping create-advisory push-snapshot update-cr-status; do
            local task_status
            task_status=$(kubectl get taskrun -n "${managed_namespace}" \
                -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask="${task}" \
                -o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || echo "SKIPPED")
            
            if [ "${task_status}" == "Succeeded" ]; then
                echo "   ✅ ${task}" >&2
            elif [ "${task_status}" == "SKIPPED" ]; then
                echo "   ⏭️  ${task}: NOT FOUND (skipped by when condition)" >&2
            else
                echo "   ❌ ${task}: ${task_status}" >&2
            fi
        done
    else
        echo "⚠️  PipelineRun not available for debugging" >&2
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Automated Verification Checks:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # ============================================================================
    # CHECK 1: Advisory URL Existence
    # ============================================================================
    echo "" >&2
    echo "1️⃣  Checking Advisory URL..." >&2
    local advisory_url
    advisory_url=$(echo "$release_json" | jq -r '.status.artifacts.advisory.url // ""' 2>/dev/null || echo "")
    local advisory_internal_url
    advisory_internal_url=$(echo "$release_json" | jq -r '.status.artifacts.advisory.internal_url // ""' 2>/dev/null || echo "")

    # Fallback: If Release CR doesn't have advisory URL (e.g., Atlas disabled, update-cr-status skipped),
    # check create-advisory TaskRun results directly
    if [ -z "$advisory_url" ] || [ "$advisory_url" == "null" ]; then
        if [ -n "$pipelinerun_name" ]; then
            echo "   ℹ️  Advisory URL not in Release CR, checking create-advisory TaskRun results..." >&2
            advisory_url=$(kubectl get taskrun -n "${managed_namespace}" \
                -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask=create-advisory \
                -o jsonpath='{.items[0].status.results[?(@.name=="advisory_url")].value}' 2>/dev/null || echo "")
            advisory_internal_url=$(kubectl get taskrun -n "${managed_namespace}" \
                -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask=create-advisory \
                -o jsonpath='{.items[0].status.results[?(@.name=="advisory_internal_url")].value}' 2>/dev/null || echo "")
        fi
    fi

    if [ -n "$advisory_url" ] && [ "$advisory_url" != "null" ]; then
        echo "   ✅ Advisory URL found: ${advisory_url}" >&2
        if [ -n "$advisory_internal_url" ] && [ "$advisory_internal_url" != "null" ]; then
            echo "   ✅ Advisory Internal URL found: ${advisory_internal_url}" >&2
        fi
    else
        echo "   ❌ FAILURE: Advisory URL not found in Release status or TaskRun results" >&2
        echo "      Problem: The create-advisory task should populate advisory_url result" >&2
        echo "      Current value: '${advisory_url}'" >&2
        echo "      Possible causes:" >&2
        echo "        - create-advisory task failed or was skipped" >&2
        echo "        - Advisory creation timed out" >&2
        echo "      How to debug:" >&2
        echo "        kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts}'" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=create-advisory -o yaml" >&2
        verification_failed=true
    fi

    # ============================================================================
    # CHECK 2: Published Images Count
    # ============================================================================
    echo "" >&2
    echo "2️⃣  Checking Published Images Count..." >&2
    local published_count
    published_count=$(echo "$release_json" | jq -r '.status.artifacts.publishedImages | length // 0' 2>/dev/null || echo "0")
    local expected_count="${LARGE_SNAPSHOT_COMPONENT_COUNT:-200}"

    # Fallback: If Release CR doesn't have publishedImages (e.g., Atlas disabled, update-cr-status skipped),
    # verify push-snapshot task succeeded and check snapshot component count
    if [ "$published_count" -eq 0 ] && [ -n "$pipelinerun_name" ]; then
        echo "   ℹ️  Published images not in Release CR, checking push-snapshot TaskRun status..." >&2
        local push_snapshot_status
        push_snapshot_status=$(kubectl get taskrun -n "${managed_namespace}" \
            -l tekton.dev/pipelineRun="${pipelinerun_name}",tekton.dev/pipelineTask=push-snapshot \
            -o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || echo "")
        
        if [ "$push_snapshot_status" == "Succeeded" ]; then
            # If push-snapshot succeeded, count components in snapshot
            local snapshot_name
            snapshot_name=$(echo "$release_json" | jq -r '.spec.snapshot // ""')
            if [ -n "$snapshot_name" ]; then
                published_count=$(kubectl get snapshot "${snapshot_name}" -n "${tenant_namespace}" \
                    -o jsonpath='{.spec.components}' 2>/dev/null | jq 'length' || echo "0")
                echo "   ✅ push-snapshot task succeeded, verified ${published_count} components in snapshot" >&2
            fi
        fi
    fi

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
        echo "        kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.publishedImages[*]}' | jq -r '.[]'" >&2
        echo "        # Check push-snapshot task logs:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=push-snapshot --sort-by=.metadata.creationTimestamp" >&2
        echo "        # Check if images were filtered:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=filter-already-released-advisory-images -o yaml" >&2
        verification_failed=true
    else
        echo "   ❌ FAILURE: No images found" >&2
        echo "      Problem: Could not verify published images count from Release CR or TaskRun results" >&2
        echo "      Published count: ${published_count}" >&2
        echo "      Possible causes:" >&2
        echo "        - push-snapshot task was skipped (check 'when' conditions)" >&2
        echo "        - push-snapshot task failed" >&2
        echo "        - apply-mapping returned mapped=false (no registry mappings configured)" >&2
        echo "        - Snapshot not found or has no components" >&2
        echo "      How to debug:" >&2
        echo "        # Check if push-snapshot ran and succeeded:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=push-snapshot -o yaml" >&2
        echo "        # Check apply-mapping results:" >&2
        echo "        kubectl get taskrun -n ${managed_namespace} -l tekton.dev/pipelineTask=apply-mapping -o jsonpath='{.items[0].status.results}'" >&2
        echo "        # Check snapshot:" >&2
        echo "        kubectl get snapshot -n ${tenant_namespace} -o yaml" >&2
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
            
            # Check task completion status first
            local task_status
            task_status=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
            local task_reason
            task_reason=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].reason}' 2>/dev/null || echo "")
            local task_message
            task_message=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].message}' 2>/dev/null || echo "")
            
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

            # Get advisory_url result
            local task_advisory_url
            task_advisory_url=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o jsonpath='{.status.results[?(@.name=="advisory_url")].value}' 2>/dev/null || echo "")
            
            if [ -n "$task_advisory_url" ] && [ "$task_advisory_url" != "null" ]; then
                echo "   ✅ Advisory URL from task: ${task_advisory_url}" >&2
            else
                if [ "$task_status" == "True" ]; then
                    echo "   ⚠️  WARNING: Advisory URL not found in task results despite task success" >&2
                    echo "      This may indicate a bug in the create-advisory task" >&2
                fi
            fi

            # Get advisory_internal_url result
            local task_advisory_internal_url
            task_advisory_internal_url=$(kubectl get taskrun "${advisory_taskrun}" -n "${managed_namespace}" \
                -o jsonpath='{.status.results[?(@.name=="advisory_internal_url")].value}' 2>/dev/null || echo "")
            
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
        echo "     ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun}" >&2
        echo "  4. Examine the Release CR status:" >&2
        echo "     kubectl get release ${release_name} -n ${tenant_namespace} -o yaml" >&2
        echo "" >&2
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
        echo "  kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.publishedImages}' | jq 'length'" >&2
        echo "  # View all published images:" >&2
        echo "  kubectl get release ${release_name} -n ${tenant_namespace} -o jsonpath='{.status.artifacts.publishedImages[*]}' | jq" >&2
        echo "" >&2
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
    : "${CONSOLE_URL:?CONSOLE_URL must be set}"

    local release_name="${large_snapshot_name}-release"

    echo "🔍 Checking Release configuration..." >&2
    echo "  Release: ${release_name}" >&2
    echo "  Namespace: ${tenant_namespace}" >&2
    
    # Display Release spec for debugging
    local release_spec
    release_spec=$(kubectl get release "${release_name}" -n "${tenant_namespace}" -o json 2>/dev/null)
    if [ -n "$release_spec" ]; then
        echo "  Snapshot: $(echo "$release_spec" | jq -r '.spec.snapshot')" >&2
        echo "  ReleasePlan: $(echo "$release_spec" | jq -r '.spec.releasePlan')" >&2
    fi
    
    # Check ReleasePlan configuration
    local release_plan_name
    release_plan_name=$(echo "$release_spec" | jq -r '.spec.releasePlan')
    if [ -n "$release_plan_name" ] && [ "$release_plan_name" != "null" ]; then
        echo "🔍 Checking ReleasePlan: ${release_plan_name}..." >&2
        local rp_info
        rp_info=$(kubectl get releaseplan "${release_plan_name}" -n "${tenant_namespace}" -o json 2>/dev/null)
        if [ -n "$rp_info" ]; then
            echo "  Application: $(echo "$rp_info" | jq -r '.spec.application')" >&2
            echo "  Target: $(echo "$rp_info" | jq -r '.spec.target')" >&2
            echo "  Labels: $(echo "$rp_info" | jq -r '.metadata.labels')" >&2
        fi
    fi

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
        echo "🔍 Debugging release-service controller state..." >&2
        
        # Check if Release has any error conditions
        local release_conditions
        release_conditions=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
            -o jsonpath='{.status.conditions}' 2>/dev/null || echo "")
        if [ -n "$release_conditions" ] && [ "$release_conditions" != "null" ]; then
            echo "  Release conditions: ${release_conditions}" >&2
        else
            echo "  ⚠️  No status conditions set on Release (controller may not be watching)" >&2
        fi
        
        # Check if there are any events related to the Release
        echo "🔍 Recent events for Release:" >&2
        kubectl get events -n "${tenant_namespace}" \
            --field-selector involvedObject.name="${release_name}" \
            --sort-by='.lastTimestamp' 2>/dev/null | tail -n 10 >&2 || true
        
        # Check ReleasePlanAdmission in target namespace
        echo "🔍 Checking ReleasePlanAdmission in ${managed_namespace}:" >&2
        kubectl get releaseplanadmission -n "${managed_namespace}" \
            -l originating-tool="${originating_tool}" 2>/dev/null >&2 || true
        
        echo "🔍 Full Release YAML:" >&2
        kubectl get release "${release_name}" -n "${tenant_namespace}" -o yaml >&2 || true
        
        return 1
    fi

    # Extract and display PipelineRun information
    local pipelinerun
    pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || echo "")

    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun}" >&2

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

        # Clean up releases created by this test (using originating-tool label)
        # This is safe because it only affects resources created by this specific test
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
                kubectl delete -f "$tmpDir/tenant-resources.yaml" 2>/dev/null || true
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

    # Now create the large snapshot
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
wait_for_releases() {
    # Validate required variables
    : "${large_snapshot_name:?large_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"

    echo "Waiting for release to start processing..." >&2
    wait_for_release_to_start || log_error "Failed to wait for release to start"

    # Export variables expected by verify_release_contents
    export RELEASE_NAME="${large_snapshot_name}-release"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    export RELEASE_NAMES="${RELEASE_NAME}"

    echo "Waiting for release pipeline to complete (this may take 4-8 hours for large snapshots)..." >&2
    "${SUITE_DIR}/../scripts/wait-for-release.sh"
}

echo "✅ Large snapshot test functions loaded"
