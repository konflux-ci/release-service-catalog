#!/usr/bin/env bash
#
# rh-advisories-large-snapshot test script
#
# INFRASTRUCTURE REQUIREMENTS:
# - Cluster: stg-rh01 (staging cluster)
# - Tenant Namespace (execution context varies):
#   * PaC runs (triggered by /test-large-snapshot): rhtap-release-2-tenant
#   * Local runs (../run-test.sh): dev-release-team-tenant (default, see test.env)
#   * Can be overridden for local runs: export tenant_namespace=rhtap-release-2-tenant
# - Managed Namespace: managed-release-team-tenant (same for all runs)
# - Required Secrets (in tenant namespace):
#   * vault-password-secret: Ansible vault password for decrypting test secrets
#   * github-token-secret: GitHub PAT with repo permissions
#   * kubeconfig-secret: Kubeconfig for cluster access
# - Required Permissions:
#   * Resource creation/deletion in both namespaces
#   * ServiceAccount with release pipeline execution permissions
#   * Access to pre-configured ReleasePlanAdmission
#
# IMPORTANT: Namespace configuration is intentionally different for isolation:
# - PaC runs execute in the namespace where the PipelineRun is created
# - Local runs default to a separate tenant for development/debugging
# - Both namespaces must have identical secret and RPA configurations
# Contact the Release Service team for access or infrastructure questions.
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# --- Timeout Configuration (in seconds, configurable via environment) ---
# Time to wait for snapshot resource to be persisted
SNAPSHOT_READY_TIMEOUT="${SNAPSHOT_READY_TIMEOUT:-60}"
SNAPSHOT_READY_POLL_INTERVAL="${SNAPSHOT_READY_POLL_INTERVAL:-2}"

# Time to wait for release to start processing
RELEASE_START_TIMEOUT="${RELEASE_START_TIMEOUT:-600}"
RELEASE_START_POLL_INTERVAL="${RELEASE_START_POLL_INTERVAL:-5}"

# Default OpenShift console URL for staging cluster (stg-rh01)
# This is the expected cluster for this test - can be overridden via environment variable
DEFAULT_CONSOLE_URL="${DEFAULT_CONSOLE_URL:-https://console-openshift-console.apps.stone-stg-rh01.l2vh.p1.openshiftapps.com}"

# Get OpenShift console URL from cluster (or use default)
# Priority: 1. CONSOLE_URL env var, 2. PaC ConfigMap, 3. DEFAULT_CONSOLE_URL
if [ -z "${CONSOLE_URL:-}" ]; then
    # Attempt to fetch from PaC ConfigMap (defensive: validate output)
    pac_console_url=$(kubectl get cm/pipelines-as-code -n openshift-pipelines -ojson 2>/dev/null | jq -r '.data."custom-console-url" // empty' 2>/dev/null || echo "")

    # Validate that we got a URL (must start with http:// or https://)
    if [[ "${pac_console_url}" =~ ^https?:// ]]; then
        CONSOLE_URL="${pac_console_url}"
        echo "📍 Using console URL from PaC ConfigMap: ${CONSOLE_URL}" >&2
    else
        # Fall back to default if ConfigMap value is invalid or unavailable
        CONSOLE_URL="${DEFAULT_CONSOLE_URL}"
        echo "📍 Using default console URL: ${CONSOLE_URL}" >&2
    fi
else
    echo "📍 Using console URL from environment: ${CONSOLE_URL}" >&2
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

    local snapshot_file="${tmpDir}/large-snapshot.yaml"

    "${SUITE_DIR}/utils/generate-large-snapshot.sh" \
        "${large_snapshot_name}" \
        "${application_name}" \
        "${tenant_namespace}" \
        "${LARGE_SNAPSHOT_COMPONENT_COUNT}" > "${snapshot_file}" || return 1

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
    pipelinerun=$(echo "$release_json" | jq -r '.status.processing.pipelineRun' 2>/dev/null || echo "")
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun}" >&2
    fi

    echo "✅ Basic release verification complete" >&2
    echo "   For large snapshots, detailed verification should be done manually" >&2
    return 0
}

# Condition check: Is release processing?
check_release_processing() {
    local release_name="$1"
    local namespace="$2"

    # Validate required parameters
    : "${release_name:?release_name parameter is required}"
    : "${namespace:?namespace parameter is required}"

    local status
    status=$(kubectl get release "${release_name}" -n "${namespace}" \
        -o jsonpath='{.status.conditions[?(@.type=="Processing")].status}' 2>/dev/null || echo "")
    [ "$status" == "True" ]
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
        -o jsonpath='{.status.processing.pipelineRun}' 2>/dev/null || echo "")

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
}

echo "✅ Large snapshot test functions loaded"
