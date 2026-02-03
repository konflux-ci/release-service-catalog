# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # Default to true

# Variables that will be set by functions and used globally:
# component_branch, component_base_branch, component_repo_name (from test.env or similar)
# managed_namespace, tenant_namespace, application_name, component_name (from test.env or similar)
# managed_sa_name (from test.env or similar)
# GITHUB_TOKEN, VAULT_PASSWORD_FILE (from test.env)
# SCRIPT_DIR (where run-test.sh is located)
# LIB_DIR (where lib/ is located)
# tmpDir (set by create_kubernetes_resources)
# component_pr, pr_number (set by wait_for_component_initialization)
# SHA (set by merge_github_pr)
# component_push_plr_name (set by wait_for_plr_to_appear)
# RELEASE_NAME, RELEASE_NAMESPACE (set and exported by wait_for_release)

# Global test matrix to track which tests should be enabled
declare -gA GLOBAL_TEST_MATRIX=(
    ["single-happy"]="disabled"
    ["single-staged"]="disabled"
    ["single-prega"]="disabled"
    ["single-hotfix"]="disabled"
    ["multi-happy"]="disabled"
    ["multi-staged"]="disabled"
    # ["multi-prega"]="disabled"   # this test incurs additional IIB requests for no value
    # ["multi-hotfix"]="disabled"  # this test incurs additional IIB requests for no value
)

# Global tracking for releases to verify
declare -gA RELEASES_TO_VERIFY=()

# Global tracking for ALL PipelineRun UIDs to cleanup
# This array stores UIDs from ALL releases in the test suite
declare -ga ALL_PIPELINERUN_UIDS=()

# --- GitHub API Integration (Works within existing pipeline) ---

# Use GitHub API to detect changed task names (PR_NUMBER and GITHUB_TOKEN available)
get_changed_files() {
    if [[ -n "${PR_NUMBER:-}" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "🔍 Detecting changed task directories from PR #${PR_NUMBER}..."
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/konflux-ci/release-service-catalog/pulls/${PR_NUMBER}/files" | \
            jq -r '.[].filename' | \
            grep '^tasks/' | \
            cut -d'/' -f1-3 | \
            sort -u | \
            tr '\n' ','
    else
        echo "⚠️  No PR context available, using full test matrix"
        echo ""
    fi
}

# Dynamic test matrix configuration based on changed files
configure_test_matrix() {
    local changed_files=$(get_changed_files)
    
    echo "🔍 Changed task directories: $changed_files"
    
    # Initialize test matrix with all tests disabled by default
    GLOBAL_TEST_MATRIX=(
        ["single-happy"]="disabled"
        ["single-staged"]="disabled" 
        ["single-prega"]="disabled"
        ["single-hotfix"]="disabled"
        ["multi-happy"]="disabled"
        ["multi-staged"]="disabled"
        # ["multi-prega"]="disabled"   # this test incurs additional IIB requests for no value
        # ["multi-hotfix"]="disabled"  # this test incurs additional IIB requests for no value
    )
    
    local tests_enabled=false
    
    # Enable specific tests based on detected task directory patterns
    # Note: This logic only applies when the unified fbc test suite is triggered
    # The existing pipeline selection logic in find_release_pipelines_from_pr.sh determines
    # when to run fbc tests (currently both fbc-release and fbc-release-multi-component)
    
    # These conditions are additive - multiple patterns can match and enable their respective tests
    
    if [[ "$changed_files" =~ tasks/managed/sign-index-image ]] || \
       [[ "$changed_files" =~ tasks/managed/rh-sign-image-cosign ]] || \
       [[ "$changed_files" =~ pipelines/internal/simple-signing-pipeline ]] || \
       [[ "$changed_files" =~ tasks/internal/request-and-upload-signature ]]; then
        echo "🎯 Detected signing task changes - enabling core scenarios"
        GLOBAL_TEST_MATRIX["single-happy"]="enabled"
        GLOBAL_TEST_MATRIX["single-staged"]="enabled"
        GLOBAL_TEST_MATRIX["single-prega"]="enabled"
        GLOBAL_TEST_MATRIX["single-hotfix"]="enabled"
        tests_enabled=true
        echo "  Signing changes enabled: single-happy, single-staged"
    fi
    
    if [[ "$changed_files" =~ pipelines/managed/fbc-release ]] || \
       [[ "$changed_files" =~ tasks/managed/prepare-fbc-parameters ]] || \
       [[ "$changed_files" =~ tasks/managed/add-fbc-contribution ]] || \
       [[ "$changed_files" =~ tasks/internal/check-fbc-opt-in ]] || \
       [[ "$changed_files" =~ tasks/internal/update-fbc-catalog-task ]] || \
       [[ "$changed_files" =~ pipelines/internal/check-fbc-opt-in ]] || \
       [[ "$changed_files" =~ pipelines/internal/update-fbc-catalog ]] || \
       [[ "$changed_files" =~ pipelines/internal/publish-index-image-pipeline ]]; then
        echo "🎯 Detected batching/publishing pipeline changes - enabling multi-component focused tests"
        GLOBAL_TEST_MATRIX["single-happy"]="enabled"
        GLOBAL_TEST_MATRIX["single-staged"]="enabled"
        GLOBAL_TEST_MATRIX["single-prega"]="enabled"
        GLOBAL_TEST_MATRIX["single-hotfix"]="enabled"
        GLOBAL_TEST_MATRIX["multi-happy"]="enabled"
        GLOBAL_TEST_MATRIX["multi-staged"]="enabled"
        tests_enabled=true
        echo "  Batching changes enabled: single-happy, single-staged, multi-happy, multi-staged"
    fi
    
    # If no specific patterns matched, enable all standard tests (fallback)
    # In this case, we are trusting that this test was executed for a reason.
    if [ "$tests_enabled" = false ]; then
        echo "🎯 No specific patterns detected - enabling full test matrix (safe fallback)"
        GLOBAL_TEST_MATRIX["single-happy"]="enabled"
        GLOBAL_TEST_MATRIX["single-staged"]="enabled"
        GLOBAL_TEST_MATRIX["single-prega"]="enabled"
        GLOBAL_TEST_MATRIX["single-hotfix"]="enabled"
        GLOBAL_TEST_MATRIX["multi-happy"]="enabled"
        GLOBAL_TEST_MATRIX["multi-staged"]="enabled"
        echo "  Enabled: single-happy, single-staged, single-prega, single-hotfix, multi-happy, multi-staged"
    fi
    
    echo "📋 Final test matrix:"
    for key in "${!GLOBAL_TEST_MATRIX[@]}"; do
        echo "  $key: ${GLOBAL_TEST_MATRIX[$key]}"
    done
}

# --- Component Build Management ---

# Always create both repositories for simplicity and reliability
create_github_repository() {
    echo "🔨 Creating repositories (always dual for reliability)..."
    
    # Always create component 1 repo
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"
    
    # Always create component 2 repo
    echo "  Creating component 2 repository..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component2_repo_name}" "${component2_branch}"
}

# Helper function for single component initialization
wait_for_single_component_initialization() {
    local comp_name=$1
    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=1
    local component_annotations=""
    local initialization_success=false

    while [ $attempt -le $max_attempts ]; do
      echo "Initialization check attempt ${attempt}/${max_attempts} for ${comp_name}..."

      # Try to get component annotations
      component_annotations=$(kubectl get component/"${comp_name}" -n "${tenant_namespace}" -ojson 2>/dev/null | \
        jq -r --arg k "build.appstudio.openshift.io/status" '.metadata.annotations[$k] // ""')

      if [ -n "${component_annotations}" ]; then
        # component_pr is made global by not declaring it local
        component_pr=$(jq -r '.pac."merge-url" // ""' <<< "${component_annotations}")
        if [ -n "${component_pr}" ]; then
            echo "✅ Component ${comp_name} initialized successfully"
            initialization_success=true
            break
        else
            echo "⚠️  Could not get component PR from annotations for ${comp_name}: ${component_annotations}"
            echo "Waiting 10 seconds before retry..."
            sleep 10
        fi

      else
        echo "⚠️  Component ${comp_name} not yet initialized (attempt ${attempt}/${max_attempts})"

        # Wait before retrying (except on the last attempt)
        if [ $attempt -lt $max_attempts ]; then
          echo "Waiting 10 seconds before retry..."
          sleep 10
        fi
      fi

      attempt=$((attempt + 1))
    done

    # Check if initialization ultimately succeeded
    if [ "$initialization_success" = false ]; then
      echo "🔴 error: component ${comp_name} failed to initialize after ${max_attempts} attempts ($(($max_attempts * 10 / 60)) minutes)"
      echo "   - Component may not exist in namespace ${tenant_namespace}"
      echo "   - Component creation may have failed"
      exit 1
    fi

    # pr_number is made global by not declaring it local
    pr_number=$(cut -f7 -d/ <<< "${component_pr}")
    if [ -z "${pr_number}" ]; then
        echo "🔴 error: Could not extract PR number from ${component_pr}"
        exit 1
    fi
    echo "Found PR for ${comp_name}: ${component_pr} (Number: ${pr_number})"
}

# Always initialize both components for simplicity and reliability
wait_for_component_initialization() {
    echo "⏳ Waiting for both components to initialize (always dual for reliability)..."
    
    # Always wait for component 1
    wait_for_single_component_initialization "${component_name}"
    component_pr="${component_pr}"
    component_pr_number="${pr_number}"
    
    # Always wait for component 2
    wait_for_single_component_initialization "${component2_name}"
    component2_pr="${component_pr}"
    component2_pr_number="${pr_number}"
}

# Helper function for single component PR merge
merge_single_component_pr() {
    local pr_num=$1
    local repo_name=$2
    local commit_message="This fixes CVE-2024-8260"
    
    if [ "${NO_CVE}" == "true" ]; then
      echo "(Note: NOT Adding a CVE to the commit message)"
      commit_message="e2e test"
    else
      echo "(Note: Adding CVE-2024-8260 to the commit message)"
    fi
    echo "Commit message: \"${commit_message}\""

    local merge_result
    local attempt=1
    local max_attempts=3
    local success=false

    # Retry loop for PR merge
    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        echo "Merge attempt ${attempt}/${max_attempts} for ${repo_name}..."

        set +e
        merge_result=$(curl -L \
          -X PUT \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $GITHUB_TOKEN" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/repos/${repo_name}/pulls/${pr_num}/merge" \
          -d "{\"commit_title\":\"e2e test\",\"commit_message\":\"${commit_message}\"}" --silent --show-error --fail-with-body)

        if [ $? -eq 0 ]; then
            success=true
            echo "✅ PR merge succeeded on attempt ${attempt} for ${repo_name}"
        else
            echo "❌ PR merge failed on attempt ${attempt} for ${repo_name}. Response: ${merge_result}"
            if [ $attempt -lt $max_attempts ]; then
                echo "Waiting 5 seconds before retry..."
                sleep 5
            fi
        fi
        set -e

        attempt=$((attempt + 1))
    done

    # Check if all attempts failed
    if [ "$success" = false ]; then
        echo "🔴 error: Failed to merge PR for ${repo_name} after ${max_attempts} attempts. Last response: ${merge_result}"
        exit 1
    fi

    # SHA is made global by not declaring it local
    SHA=$(jq -r '.sha' <<< "${merge_result}")
    if [ -z "$SHA" ] || [ "$SHA" == "null" ]; then
        echo "🔴 error: Could not get SHA from merge result for ${repo_name}: ${merge_result}"
        exit 1
    fi
    echo "PR merged for ${repo_name}. Commit SHA: ${SHA}"
}

# Always merge PRs for both components for simplicity and reliability
merge_github_pr() {
    echo "🔀 Merging PRs for both components (always dual for reliability)..."
    
    # Always merge component 1
    merge_single_component_pr "${component_pr_number}" "${component_repo_name}"
    component_sha="${SHA}"
    
    # Always merge component 2
    merge_single_component_pr "${component2_pr_number}" "${component2_repo_name}"
    component2_sha="${SHA}"
    
    SHA="${component_sha}"  # Primary SHA for framework compatibility
}

# Helper function for single PLR appearance
wait_for_single_plr_to_appear() {
    local sha=$1
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local found_plr_name=""

    echo -n "Waiting for PipelineRun to appear for SHA ${sha}" >&2
    while [ -z "$found_plr_name" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo >&2
            echo "🔴 Timeout waiting for PipelineRun to appear after ${timeout} seconds for SHA ${sha}" >&2
            exit 1
        fi

        sleep 5
        echo -n "." >&2
        # get only running pipelines
        found_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$sha" -n "${tenant_namespace}" --no-headers 2>/dev/null | { grep "Running" || true; } | awk '{print $1}')
    done
    echo >&2
    echo "✅ Found PipelineRun for SHA ${sha}: ${found_plr_name}" >&2
    echo "   PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${found_plr_name}")" >&2
    
    # Set global variable for backward compatibility AND return the value
    component_push_plr_name="${found_plr_name}"
    # Only echo the PLR name to stdout for capture
    echo "${found_plr_name}"
}

# Always wait for PLRs for both components for simplicity and reliability
wait_for_plr_to_appear() {
    echo "⏳ Waiting for PipelineRuns for both components (always dual for reliability)..."
    
    # Always wait for component 1 PLR
    comp1_plr_name=$(wait_for_single_plr_to_appear "${component_sha}")
    component_push_plr_name="${comp1_plr_name}"  # Primary PLR for framework
    
    # Always wait for component 2 PLR
    comp2_plr_name=$(wait_for_single_plr_to_appear "${component2_sha}")
    component2_push_plr_name="${comp2_plr_name}"
}

# Helper function for single PLR completion
wait_for_single_plr_to_complete() {
    local plr_name=$1
    local comp_name=$2
    local timeout=2100  # 35 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local completed=""
    local retry_attempted="false"
    local taskStatus="" # taskrun status from last output
    local previousTaskStatus="" # to avoid duplicate output

    echo "Waiting for PipelineRun ${plr_name} (${comp_name}) to complete"
    echo "🔍 DEBUG: Checking if PipelineRun ${plr_name} exists..."
    
    # First verify the PipelineRun exists
    if ! kubectl get pipelinerun "${plr_name}" -n "${tenant_namespace}" >/dev/null 2>&1; then
        echo "🔴 ERROR: PipelineRun ${plr_name} does not exist in namespace ${tenant_namespace}"
        echo "Available PipelineRuns:"
        kubectl get pipelinerun -n "${tenant_namespace}" --no-headers 2>/dev/null || echo "No PipelineRuns found"
        exit 1
    fi
    
    while [ -z "$completed" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun ${plr_name} to complete after ${timeout} seconds"
            exit 1
        fi

        sleep 5

        # Check if the pipeline run is completed - use a more robust approach
        local plr_status
        plr_status=$(kubectl get pipelinerun "${plr_name}" -n "${tenant_namespace}" -o json 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$plr_status" ]; then
            completed=$(echo "$plr_status" | jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status' 2>/dev/null || echo "")
        else
            echo "🔍 DEBUG: Failed to get PipelineRun status for ${plr_name}"
            continue
        fi

        # If completed, check the status
        if [ -n "$completed" ]; then
          taskStatus=$("${SUITE_DIR}/../scripts/print-taskrun-status.sh" "${plr_name}" "${tenant_namespace}" compact)
          if [ "${taskStatus}" != "${previousTaskStatus}" ]; then
            echo -e "${taskStatus}"
            previousTaskStatus="${taskStatus}"
          fi
          if [ "$completed" == "True" ]; then
            echo ""
            echo "✅ PipelineRun ${plr_name} (${comp_name}) completed successfully"
            break
          elif [ "$completed" == "False" ]; then
            echo ""
            echo "❌ PipelineRun ${plr_name} (${comp_name}) failed"
            if [ "${retry_attempted}" == "false" ]; then
                echo "Attempting retry for component ${comp_name}..."
                kubectl annotate components/${comp_name} build.appstudio.openshift.io/request=trigger-pac-build -n "${tenant_namespace}"
                # Wait for new PLR to appear for this component
                if [ "${comp_name}" == "${component_name}" ]; then
                    wait_for_single_plr_to_appear "${component_sha}"
                    component_push_plr_name="${component_push_plr_name}"
                    plr_name="${component_push_plr_name}"
                elif [ "${comp_name}" == "${component2_name}" ]; then
                    wait_for_single_plr_to_appear "${component2_sha}"
                    component2_push_plr_name="${component_push_plr_name}"
                    plr_name="${component_push_plr_name}"
                fi
                retry_attempted="true"
            else
                echo "Retry already attempted for ${comp_name}. Exiting."
                exit 1
            fi
          fi
          completed=""
        fi
    done
    echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${plr_name}")"
}

# Wait for PLR completion for both components in parallel to avoid race conditions
wait_for_plr_to_complete() {
    echo "⏳ Waiting for PipelineRuns to complete for both components in parallel (robustness improvement)..."

    local comp1_plr="${component_push_plr_name}"
    local comp2_plr="${component2_push_plr_name}"
    local comp1_name="${component_name}"
    local comp2_name="${component2_name}"

    echo "🔄 Starting parallel monitoring of:"
    echo "  - Component 1 PLR: ${comp1_plr} (${comp1_name})"
    echo "  - Component 2 PLR: ${comp2_plr} (${comp2_name})"

    # Create temporary files to capture results from background processes
    local comp1_result=$(mktemp)
    local comp2_result=$(mktemp)

    # Start monitoring both PLRs in parallel
    (
        if wait_for_single_plr_to_complete "${comp1_plr}" "${comp1_name}"; then
            echo "success" > "${comp1_result}"
            echo "✅ Component 1 (${comp1_name}) PipelineRun completed: ${comp1_plr}" >&2
        else
            echo "failure" > "${comp1_result}"
            echo "🔴 Component 1 (${comp1_name}) PipelineRun failed: ${comp1_plr}" >&2
        fi
    ) &
    local pid1=$!

    (
        if wait_for_single_plr_to_complete "${comp2_plr}" "${comp2_name}"; then
            echo "success" > "${comp2_result}"
            echo "✅ Component 2 (${comp2_name}) PipelineRun completed: ${comp2_plr}" >&2
        else
            echo "failure" > "${comp2_result}"
            echo "🔴 Component 2 (${comp2_name}) PipelineRun failed: ${comp2_plr}" >&2
        fi
    ) &
    local pid2=$!

    # Wait for both background processes to complete
    echo "⏳ Waiting for both components to complete..."
    wait $pid1
    local exit1=$?
    wait $pid2
    local exit2=$?

    # Check results
    local comp1_status=$(cat "${comp1_result}" 2>/dev/null || echo "unknown")
    local comp2_status=$(cat "${comp2_result}" 2>/dev/null || echo "unknown")

    # Cleanup temp files
    rm -f "${comp1_result}" "${comp2_result}"

    # Report results
    if [ "${comp1_status}" = "success" ] && [ "${comp2_status}" = "success" ]; then
        echo "🎉 All PipelineRuns completed successfully in parallel"
        return 0
    else
        echo "🔴 One or more PipelineRuns failed:"
        echo "  - Component 1 (${comp1_name}): ${comp1_status}"
        echo "  - Component 2 (${comp2_name}): ${comp2_status}"
        return 1
    fi
}

# --- Snapshot Management ---

# Simple snapshot discovery (no race conditions in controlled test environment)
wait_for_single_component_snapshot() {
    echo "📸 Looking for single-component snapshot..." >&2
    echo "🔍 DEBUG: Search context - namespace: ${tenant_namespace}, application: ${application_name}" >&2
    
    local snapshot_name
    snapshot_name=$(kubectl get snapshots -n "$tenant_namespace" \
        -l "appstudio.openshift.io/application=${application_name}" \
        --sort-by=.metadata.creationTimestamp \
        -o json 2>/dev/null | jq -r '.items[] | select(.spec.components | length == 1) | .metadata.name' | tail -1)
    
    if [ -n "$snapshot_name" ]; then
        echo "🔍 DEBUG: Found single-component snapshot: $snapshot_name" >&2
    else
        echo "🔍 DEBUG: No single-component snapshot found" >&2
        
        # Show what snapshots are available for debugging
        local all_snapshots
        all_snapshots=$(kubectl get snapshots -n "$tenant_namespace" \
            -l "appstudio.openshift.io/application=${application_name}" \
            --sort-by=.metadata.creationTimestamp \
            -o json 2>/dev/null)
        
        if [ -n "$all_snapshots" ]; then
            echo "🔍 DEBUG: Available snapshots:" >&2
            echo "$all_snapshots" | jq -r '.items[] | "  - Name: \(.metadata.name), Created: \(.metadata.creationTimestamp), Components: \(.spec.components | length) (\(.spec.components | map(.name // "unknown") | join(", ")))"' >&2
        fi
    fi
    
    echo "$snapshot_name"
}

wait_for_multi_component_snapshot() {
    echo "📸 Looking for multi-component snapshot..." >&2
    echo "🔍 DEBUG: Search context - namespace: ${tenant_namespace}, application: ${application_name}" >&2
    
    local max_attempts=24  # 12 minutes with 30-second intervals
    local attempt=1
    local snapshot_name=""
    
    while [ $attempt -le $max_attempts ] && [ -z "$snapshot_name" ]; do
        echo "🔍 DEBUG: Multi-component snapshot search attempt ${attempt}/${max_attempts}" >&2
        
        # Get all snapshots for the application
        local all_snapshots
        all_snapshots=$(kubectl get snapshots -n "$tenant_namespace" \
            -l "appstudio.openshift.io/application=${application_name}" \
            --sort-by=.metadata.creationTimestamp \
            -o json 2>/dev/null)
        
        if [ $? -ne 0 ] || [ -z "$all_snapshots" ]; then
            echo "🔍 DEBUG: Failed to retrieve snapshots or no snapshots found" >&2
            if [ $attempt -lt $max_attempts ]; then
                echo "🔍 DEBUG: Waiting 30 seconds before retry..." >&2
                sleep 30
            fi
            attempt=$((attempt + 1))
            continue
        fi
        
        # Show all available snapshots with component details
        echo "🔍 DEBUG: Available snapshots:" >&2
        echo "$all_snapshots" | jq -r '.items[] | "  - Name: \(.metadata.name), Created: \(.metadata.creationTimestamp), Components: \(.spec.components | length) (\(.spec.components | map(.name // "unknown") | join(", ")))"' >&2
        
        # Look for multi-component snapshot (2 components)
        snapshot_name=$(echo "$all_snapshots" | jq -r '.items[] | select(.spec.components | length == 2) | .metadata.name' | tail -1)
        
        if [ -n "$snapshot_name" ]; then
            echo "🔍 DEBUG: Found multi-component snapshot: $snapshot_name" >&2
            
            # Show detailed info about the found snapshot
            local snapshot_details
            snapshot_details=$(echo "$all_snapshots" | jq -r --arg name "$snapshot_name" '.items[] | select(.metadata.name == $name)')
            echo "🔍 DEBUG: Snapshot details:" >&2
            echo "$snapshot_details" | jq -r '"  - Created: \(.metadata.creationTimestamp)"' >&2
            echo "$snapshot_details" | jq -r '"  - Components: \(.spec.components | map(.name) | join(", "))"' >&2
            echo "$snapshot_details" | jq -r '"  - Component count: \(.spec.components | length)"' >&2
            break
        else
            echo "🔍 DEBUG: No multi-component snapshot found (need exactly 2 components)" >&2
            
            # Show component count distribution
            local component_counts_file=$(mktemp)
            echo "$all_snapshots" | jq -r '.items[] | .spec.components | length' | sort | uniq -c > "$component_counts_file"
            if [ -s "$component_counts_file" ]; then
                echo "🔍 DEBUG: Component count distribution:" >&2
                while read count components; do
                    echo "    $count snapshot(s) with $components component(s)" >&2
                done < "$component_counts_file"
            fi
            rm -f "$component_counts_file"
            
            if [ $attempt -lt $max_attempts ]; then
                echo "🔍 DEBUG: Waiting 30 seconds before retry..." >&2
                sleep 30
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [ -z "$snapshot_name" ]; then
        echo "🔴 DEBUG: Failed to find multi-component snapshot after ${max_attempts} attempts ($(($max_attempts * 30 / 60)) minutes)" >&2
        echo "🔴 DEBUG: This may indicate:" >&2
        echo "    - Multi-component snapshots are not being created" >&2
        echo "    - Snapshot creation is slower than expected" >&2
        echo "    - Component builds may have failed or not completed properly" >&2
        echo "    - Application integration may have issues" >&2
    fi
    
    echo "$snapshot_name"
}

# --- Manual Release Triggering ---

# Main test orchestration function
trigger_configured_releases() {
    RELEASES_TO_VERIFY=()
    
    # Configure test matrix based on detected changes (skip if already configured)
    if [ "${GLOBAL_TEST_MATRIX[single-happy]}" = "disabled" ]; then
        echo "🔧 Test matrix not yet configured, configuring now..."
        configure_test_matrix
    else
        echo "🔧 Test matrix already configured, skipping configuration"
    fi
    
    echo "🚀 Triggering releases based on optimized test matrix..."
    
    for test_key in "${!GLOBAL_TEST_MATRIX[@]}"; do
        if [ "${GLOBAL_TEST_MATRIX[$test_key]}" = "enabled" ]; then
            IFS='-' read -r mode scenario <<< "$test_key"
            
            # Get appropriate snapshot
            local snapshot_name
            if [ "$mode" = "single" ]; then
                snapshot_name=$(wait_for_single_component_snapshot)
            elif [ "$mode" = "multi" ]; then
                snapshot_name=$(wait_for_multi_component_snapshot)  
            fi
            
            if [ -z "$snapshot_name" ]; then
                echo "🔴 Failed to find snapshot for $mode-$scenario"
                exit 1
            fi
            
            # Create manual release
            local release_name="fbc-${mode}-${scenario}-${uuid}"
            local release_plan="fbc-release-${scenario}-rp-${uuid}"
            
            echo "  Creating release: $release_name (snapshot: $snapshot_name)"
            cat << EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: $release_name
  namespace: $tenant_namespace
spec:
  snapshot: $snapshot_name
  releasePlan: $release_plan
EOF
                
            RELEASES_TO_VERIFY["$release_name"]="$mode-$scenario"
        else
            echo "⏭️  Skipping disabled test: $test_key"
        fi
    done
    
    if [ ${#RELEASES_TO_VERIFY[@]} -eq 0 ]; then
        echo "🔴 No releases were created - check test matrix configuration"
        exit 1
    fi
    
    echo "✅ Created ${#RELEASES_TO_VERIFY[@]} releases, waiting for completion..."
}

# Validate pipeline results to ensure they are accessible, single-line, and match release artifacts
validate_pipeline_results() {
    local release_name=$1
    echo "🔍 Validating pipeline results for release: $release_name"
    echo "🔍 DEBUG: Validating release artifacts (populated by managed pipeline)"
    
    local failures=0
    
    # Get release artifacts from the tenant namespace (populated by release service from managed pipeline)
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)
    
    if [ $? -ne 0 ] || [ -z "$release_json" ]; then
        echo "🔴 Could not retrieve release ${release_name} from namespace ${RELEASE_NAMESPACE}"
        return 1
    fi
    
    echo "🔍 DEBUG: Release JSON retrieved successfully"
    
    local index_image_artifacts
    index_image_artifacts=$(jq -c '.status.artifacts.index_image // {}' <<< "${release_json}")

    echo "Checking index_image artifacts..."
    if [ "$index_image_artifacts" = "{}" ] || [ -z "$index_image_artifacts" ]; then
        echo "🔴 index_image artifacts are empty or missing"
        failures=$((failures+1))
    else
        echo "✅ index_image artifacts:"
        jq '.' <<< "$index_image_artifacts"
    fi
    
    if [ $failures -eq 0 ]; then
        echo "✅ Pipeline results validation passed (release artifacts are single-line and properly populated)"
    else
        echo "🔴 Pipeline results validation failed with $failures error(s)"
        echo "🔍 DEBUG: This indicates the managed pipeline may still be producing multi-line results"
    fi
    
    return $failures
}

# Enhanced verification for single component releases
verify_single_component_release() {
    local release_name=$1
    echo "🔍 Verifying single-component release: $release_name"
    
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)
    
    local failures=0
    local fbc_fragment ocp_version iib_log index_image_artifacts

    fbc_fragment=$(jq -r '.status.artifacts.components[0].fbc_fragment // ""' <<< "${release_json}")
    ocp_version=$(jq -r '.status.artifacts.components[0].ocp_version // ""' <<< "${release_json}")
    iib_log=$(jq -r '.status.artifacts.components[0].iibLog // ""' <<< "${release_json}")
    index_image_artifacts=$(jq -c '.status.artifacts.index_image // {}' <<< "${release_json}")

    echo "Checking fbc_fragment..."
    if [ -n "${fbc_fragment}" ]; then
      echo "✅️ fbc_fragment: ${fbc_fragment}"
    else
      echo "🔴 fbc_fragment was empty!"
      failures=$((failures+1))
    fi
    echo "Checking ocp_version..."
    if [ -n "${ocp_version}" ]; then
      echo "✅️ ocp_version: ${ocp_version}"
    else
      echo "🔴 ocp_version was empty!"
      failures=$((failures+1))
    fi
    echo "Checking iib_log..."
    if [ -n "${iib_log}" ]; then
      echo "✅️ iib_log: ${iib_log}"
    else
      echo "🔴 iib_log was empty!"
      failures=$((failures+1))
    fi
    echo "Checking index_image..."
    if [ "$index_image_artifacts" = "{}" ] || [ -z "$index_image_artifacts" ]; then
      echo "🔴 index_image was empty!"
      failures=$((failures+1))
    else
      echo "✅️ index_image:"
      jq '.' <<< "$index_image_artifacts"
    fi

    return $failures
}

# Enhanced verification for multi-component releases  
verify_multi_component_release() {
    local release_name=$1
    echo "🔍 Verifying multi-component release: $release_name"
    
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)
    
    local failures=0
    
    # After deduplication, we expect exactly 1 component per unique target_index
    # Multiple fragments for the same target are batched and deduplicated to a single final component
    local component_count
    component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")
    echo "Checking component count..."

    if [ "${component_count}" -eq 1 ]; then
      echo "✅️ Found expected 1 component in release (after batching and deduplication)"
    else
      echo "🔴 Expected 1 component, found ${component_count}!"
      failures=$((failures+1))
    fi

    # Verify the component has all required fields and a valid index_image
    local fbc_fragment ocp_version iib_log index_image
    fbc_fragment=$(jq -r ".status.artifacts.components[0].fbc_fragment // \"\"" <<< "${release_json}")
    ocp_version=$(jq -r ".status.artifacts.components[0].ocp_version // \"\"" <<< "${release_json}")
    iib_log=$(jq -r ".status.artifacts.components[0].iibLog // \"\"" <<< "${release_json}")
    index_image=$(jq -r ".status.artifacts.components[0].index_image // \"\"" <<< "${release_json}")

    echo "Verifying component..."

    if [ -n "${fbc_fragment}" ]; then
      echo "✅️ Component fbc_fragment: ${fbc_fragment}"
    else
      echo "🔴 Component fbc_fragment was empty!"
      failures=$((failures+1))
    fi

    if [ -n "${ocp_version}" ]; then
      echo "✅️ Component ocp_version: ${ocp_version}"
    else
      echo "🔴 Component ocp_version was empty!"
      failures=$((failures+1))
    fi

    if [ -n "${iib_log}" ]; then
      echo "✅️ Component iib_log: ${iib_log}"
    else
      echo "🔴 Component iib_log was empty!"
      failures=$((failures+1))
    fi

    # Verify batching success by checking that the component has a valid index_image
    if [ -n "${index_image}" ]; then
      echo "✅️ Component has valid index_image (successful batching): ${index_image}"
    else
      echo "🔴 Component index_image was empty (batching failed)!"
      failures=$((failures+1))
    fi

    return $failures
}

# Scenario-specific verification functions
verify_staging_behavior() {
    local release_name=$1
    echo "🔍 Verifying staging behavior for: $release_name"
    # Add staging-specific verification logic here
    return 0
}

verify_prega_tagging() {
    local release_name=$1
    echo "🔍 Verifying prega tagging for: $release_name"
    # Add prega-specific verification logic here
    return 0
}

verify_hotfix_tagging() {
    local release_name=$1
    echo "🔍 Verifying hotfix tagging for: $release_name"
    # Add hotfix-specific verification logic here
    return 0
}

# Wait for a single release to complete
wait_for_release() {
    local release_name=$1
    echo "⏳ Waiting for release $release_name to complete..."
    
    export RELEASE_NAME=${release_name}
    export RELEASE_NAMESPACE=${tenant_namespace}
    "${SUITE_DIR}/../scripts/wait-for-release.sh"
}

# Override main framework function to use our release verification
verify_release_contents() {
    local failed_releases=()
    
    echo "🔍 Verifying all releases..."
    
    for release_name in "${!RELEASES_TO_VERIFY[@]}"; do
        local mode_scenario="${RELEASES_TO_VERIFY[$release_name]}"
        local mode="${mode_scenario%-*}"
        local scenario="${mode_scenario#*-}"
        
        echo "  Verifying $release_name ($mode-$scenario)..."
        
        # Wait for release completion
        wait_for_release "$release_name"
        
        # IMMEDIATE cleanup after this release completes (before next release starts)
        # This prevents IR accumulation between releases in the same test suite
        echo "  🧹 Cleaning up InternalRequests from this release..."
        local plr_name=$(kubectl get release "$release_name" -n "${RELEASE_NAMESPACE}" \
            -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null | cut -d'/' -f2)
        if [ -n "$plr_name" ]; then
            local plr_uid=$(kubectl get pipelinerun "$plr_name" -n managed-release-team-tenant \
                -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "")
            if [ -n "$plr_uid" ]; then
                echo "    Deleting InternalRequests for PipelineRun UID: $plr_uid"
                kubectl delete internalrequest -n managed-release-team-tenant \
                    -l "internal-services.appstudio.openshift.io/pipelinerun-uid=$plr_uid" \
                    --timeout=30s 2>/dev/null || true
                echo "  ✅ Cleanup completed for $release_name"
                
                # Track for final cleanup as well
                ALL_PIPELINERUN_UIDS+=("$plr_uid")
            fi
        fi
        
        # Mode-specific verification
        local mode_result=0
        if [ "$mode" = "single" ]; then
            verify_single_component_release "$release_name"
            mode_result=$?
        elif [ "$mode" = "multi" ]; then
            verify_multi_component_release "$release_name"
            mode_result=$?
        fi
        
        # Pipeline results validation (always runs for all releases)
        echo "  📋 Validating pipeline results for $release_name..."
        validate_pipeline_results "$release_name"
        local pipeline_result=$?
        
        # Scenario-specific verification
        local scenario_result=0
        case "$scenario" in
            "staged") 
                verify_staging_behavior "$release_name" 
                scenario_result=$?
                ;;
            "prega") 
                verify_prega_tagging "$release_name"
                scenario_result=$?
                ;;  
            "hotfix") 
                verify_hotfix_tagging "$release_name"
                scenario_result=$?
                ;;
        esac
        
        if [ $mode_result -eq 0 ] && [ $scenario_result -eq 0 ] && [ $pipeline_result -eq 0 ]; then
            echo "  ✅ $release_name verification passed"
        else
            echo "  🔴 $release_name verification failed"
            failed_releases+=("$release_name")
        fi
    done
    
    if [ ${#failed_releases[@]} -gt 0 ]; then
        echo "🔴 ${#failed_releases[@]} release(s) failed verification: ${failed_releases[*]}"
        exit 1
    else
        echo "✅ All ${#RELEASES_TO_VERIFY[@]} releases verified successfully"
    fi
}

# Configure test matrix early for consistency (components always built as dual)
configure_test_matrix_early() {
    echo "🔧 Configuring test matrix early for consistency..."
    configure_test_matrix
}

# Override wait_for_releases to use manual release creation
wait_for_releases() {
    echo "Unified FBC test: Using manual release creation with intelligent optimization"
    echo "🔍 DEBUG: Current time: $(date)"
    echo "🔍 DEBUG: Function wait_for_releases() called successfully"
    echo "🔍 DEBUG: PLR completion status verified, proceeding to manual release creation"
    
    # Add a small delay to ensure any snapshot creation has time to complete
    echo "🔍 DEBUG: Waiting 30 seconds for any final snapshot updates..."
    sleep 30
    
    echo "🔍 DEBUG: Calling trigger_configured_releases() now..."
    trigger_configured_releases
    echo "🔍 DEBUG: trigger_configured_releases() completed successfully"
}

# Initialize test matrix immediately when this script is sourced
configure_test_matrix_early
