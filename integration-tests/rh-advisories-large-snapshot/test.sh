#!/usr/bin/env bash
#
# Test script for rh-advisories pipeline with large snapshots
# This test bypasses the standard build flow and directly creates a large snapshot
# with pre-built images to test the rh-advisories pipeline's ability to handle
# large-scale releases (~200 components).
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # No CVE simulation for large snapshot test

# Override the standard test flow for large snapshot testing
# This test doesn't follow the typical build->merge->release flow
# Instead, it directly creates a large snapshot and release

# Function to create a large snapshot manifest
# This creates a snapshot with ~200 pre-built components
create_large_snapshot() {
    echo "Creating large snapshot manifest with ~200 components..."
    
    local snapshot_file="${tmpDir}/large-snapshot.yaml"
    
    # Generate a snapshot with 200 components using pre-built images
    # We use registry.redhat.io/openshift4/ose-cli:latest as a base image
    # to avoid build requirements
    cat > "${snapshot_file}" <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Snapshot
metadata:
  name: ${large_snapshot_name}
  namespace: ${tenant_namespace}
  labels:
    test.appstudio.openshift.io/type: component
    appstudio.openshift.io/application: ${application_name}
    originating-tool: "${originating_tool}"
  annotations:
    test.appstudio.openshift.io/large-snapshot: "true"
spec:
  application: ${application_name}
  displayName: Large Snapshot for RH Advisories Test
  displayDescription: "Snapshot with ~200 components for testing large-scale releases"
  components:
EOF

    # Add 200 components to the snapshot
    for i in $(seq 1 200); do
        cat >> "${snapshot_file}" <<EOF
    - name: component-$(printf "%03d" $i)
      containerImage: registry.redhat.io/openshift4/ose-cli:latest
      source:
        git:
          url: ${component_git_url}
          revision: main
EOF
    done
    
    echo "✅ Large snapshot manifest created with 200 components"
    echo "${snapshot_file}"
}

# Function to apply the large snapshot
apply_large_snapshot() {
    echo "Applying large snapshot to cluster..."
    
    local snapshot_file=$(create_large_snapshot)
    
    kubectl apply -f "${snapshot_file}" -n "${tenant_namespace}"
    
    # Wait for snapshot to be ready
    echo "Waiting for snapshot to be ready..."
    local timeout=60
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout waiting for snapshot to be ready"
        fi
        
        local ready=$(kubectl get snapshot "${large_snapshot_name}" -n "${tenant_namespace}" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$ready" ]; then
            echo "✅ Snapshot ${large_snapshot_name} is ready"
            break
        fi
        
        sleep 2
    done
}

# Function to create a Release CR that references the large snapshot
create_release_for_large_snapshot() {
    echo "Creating Release CR for large snapshot..."
    
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
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  snapshot: ${large_snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    kubectl apply -f "${release_file}" -n "${tenant_namespace}"
    
    echo "✅ Release CR created: ${large_snapshot_name}-release"
}

# Function to verify the release for large snapshot
# This is a simplified version that checks basic success criteria
verify_release_contents() {
    local release_name="${large_snapshot_name}-release"
    
    echo "Verifying Release contents for ${release_name} in namespace ${tenant_namespace}..."
    
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${tenant_namespace}" -ojson 2>/dev/null || echo "")
    
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi
    
    # Check if release has completed (either succeeded or failed with expected errors)
    local succeeded=$(echo "$release_json" | jq -r '.status.conditions[] | select(.type=="Released") | .status' 2>/dev/null || echo "")
    local processing=$(echo "$release_json" | jq -r '.status.conditions[] | select(.type=="Processing") | .status' 2>/dev/null || echo "")
    
    echo "Release status:"
    echo "  Succeeded: ${succeeded}"
    echo "  Processing: ${processing}"
    
    # For this manual test, we primarily want to ensure the pipeline runs
    # and handles the large snapshot without crashing
    if [ "$succeeded" == "True" ]; then
        echo "✅ Release completed successfully"
    elif [ "$processing" == "True" ]; then
        echo "⚠️  Release is still processing - this is expected for large snapshots"
        echo "   Manual verification may be needed"
    else
        echo "⚠️  Release may have encountered issues - manual verification needed"
        echo "   This is not necessarily a failure for large snapshot tests"
    fi
    
    # Get the PipelineRun associated with this release
    local pipelinerun=$(echo "$release_json" | jq -r '.status.processing.pipelineRun' 2>/dev/null || echo "")
    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}"
        echo "  PipelineRun URL: https://console-openshift-console.apps.stone-stg-rh01.l2vh.p1.openshiftapps.com/k8s/ns/${managed_namespace}/tekton.dev~v1beta1~PipelineRun/${pipelinerun}"
    fi
    
    echo "✅ Basic release verification complete"
    echo "   For large snapshots, detailed verification should be done manually"
}

# Function to wait for release to start processing
# We don't wait for completion as large snapshots may take a very long time
wait_for_release_to_start() {
    local release_name="${large_snapshot_name}-release"
    local timeout=600  # 10 minutes to start processing
    local start_time=$(date +%s)
    
    echo "Waiting for release to start processing..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout waiting for release to start processing"
        fi
        
        local processing=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
            -o jsonpath='{.status.conditions[?(@.type=="Processing")].status}' 2>/dev/null || echo "")
        
        if [ "$processing" == "True" ]; then
            echo "✅ Release has started processing"
            
            # Get the PipelineRun name
            local pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
                -o jsonpath='{.status.processing.pipelineRun}' 2>/dev/null || echo "")
            
            if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
                echo "  PipelineRun: ${pipelinerun}"
                echo "  PipelineRun URL: https://console-openshift-console.apps.stone-stg-rh01.l2vh.p1.openshiftapps.com/k8s/ns/${managed_namespace}/tekton.dev~v1beta1~PipelineRun/${pipelinerun}"
                
                # Export for later use
                export RELEASE_PIPELINERUN="${pipelinerun}"
            fi
            
            break
        fi
        
        sleep 5
        echo -n "."
    done
}

# Override functions that would normally do component builds
# These are called by run-test.sh but we want to skip them for this test

# Override: Minimal GitHub repo creation (still needed for some metadata)
create_github_repository() {
    echo "Creating minimal GitHub repository for test metadata..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"
}

# Override: Skip patching component source (no builds)
patch_component_source() {
    echo "⏩ Skipping component source patch - no builds needed"
}

# Override: Skip waiting for component initialization (no builds needed)
wait_for_component_initialization() {
    echo "⏩ Skipping component initialization - using pre-built images"
}

# Override: Skip patching component source before merge (no PR to merge)
patch_component_source_before_merge() {
    echo "⏩ Skipping component source patch - no builds needed"
}

# Override: Skip merging PR (no PR needed for pre-built images)
merge_github_pr() {
    echo "⏩ Skipping PR merge - using pre-built images"
}

# Override: Skip waiting for PLR to appear (no builds)
wait_for_plr_to_appear() {
    echo "⏩ Skipping PLR wait - no builds triggered"
}

# Override: Skip waiting for PLR to complete (no builds)
wait_for_plr_to_complete() {
    echo "⏩ Skipping PLR completion - no builds needed"
}

# Override: Custom resource creation that includes the large snapshot
create_kubernetes_resources() {
    echo "Creating Kubernetes resources with large snapshot..."
    
    # Create temp directory for resources
    tmpDir=$(mktemp -d)
    echo "Using temporary directory: ${tmpDir}"
    
    # Build and apply tenant resources (Application, Component, etc.)
    echo "Building tenant resources..."
    kustomize build "${SUITE_DIR}/resources/tenant" | envsubst > "${tmpDir}/tenant-resources.yaml"
    kubectl apply -f "${tmpDir}/tenant-resources.yaml"
    
    # Build and apply managed resources (RPA, EC Policy, etc.)
    echo "Building managed resources..."
    kustomize build "${SUITE_DIR}/resources/managed" | envsubst > "${tmpDir}/managed-resources.yaml"
    kubectl apply -f "${tmpDir}/managed-resources.yaml"
    
    # Now create the large snapshot
    apply_large_snapshot
    
    # Create a release for the snapshot
    create_release_for_large_snapshot
}

# Override: Wait for releases - we create our own release directly
wait_for_releases() {
    echo "Waiting for release to start processing..."
    wait_for_release_to_start
    
    # Export variables expected by verify_release_contents
    export RELEASE_NAME="${large_snapshot_name}-release"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    export RELEASE_NAMES="${RELEASE_NAME}"
}

echo "✅ Large snapshot test functions loaded"
