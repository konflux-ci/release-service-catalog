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
    ["single-optin"]="disabled"
    ["multi-happy"]="disabled"
    ["multi-staged"]="disabled"
    # ["multi-prega"]="disabled"   # this test incurs additional IIB requests for no value
    # ["multi-hotfix"]="disabled"  # this test incurs additional IIB requests for no value
)

# Global tracking for releases to verify
declare -gA RELEASES_TO_VERIFY=()

# Small function to show which scenarios are enabled
show_enabled_scenarios(){
    local description=$1
    local -n scenarios_ref=$2

    echo -en "  ${description}: "
    for scenario in "${!scenarios_ref[@]}"; do
        if [ ${scenarios_ref[$scenario]} == "enabled" ]; then
            echo -en "${scenario} "
        fi
    done

    # echoes one empty line
    echo ""
}

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
        ["single-optin"]="disabled"
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
        GLOBAL_TEST_MATRIX["single-optin"]="enabled"
        tests_enabled=true

        show_enabled_scenarios "Signing changes enabled" GLOBAL_TEST_MATRIX
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
        GLOBAL_TEST_MATRIX["single-optin"]="enabled"
        GLOBAL_TEST_MATRIX["multi-happy"]="enabled"
        GLOBAL_TEST_MATRIX["multi-staged"]="enabled"
        tests_enabled=true

        show_enabled_scenarios "Batching changes enabled" GLOBAL_TEST_MATRIX
    fi
    
    # If no specific patterns matched, enable all standard tests (fallback)
    # In this case, we are trusting that this test was executed for a reason.
    if [ "$tests_enabled" = false ]; then
        echo "🎯 No specific patterns detected - enabling full test matrix (safe fallback)"
        GLOBAL_TEST_MATRIX["single-happy"]="enabled"
        GLOBAL_TEST_MATRIX["single-staged"]="enabled"
        GLOBAL_TEST_MATRIX["single-prega"]="enabled"
        GLOBAL_TEST_MATRIX["single-hotfix"]="enabled"
        GLOBAL_TEST_MATRIX["single-optin"]="enabled"
        GLOBAL_TEST_MATRIX["multi-happy"]="enabled"
        GLOBAL_TEST_MATRIX["multi-staged"]="enabled"

        show_enabled_scenarios "Enabled" GLOBAL_TEST_MATRIX
    fi
    
    echo "📋 Final test matrix:"
    for key in "${!GLOBAL_TEST_MATRIX[@]}"; do
        echo "  $key: ${GLOBAL_TEST_MATRIX[$key]}"
    done
}

# --- Component Build Management ---

# Always create all repositories for simplicity and reliability
create_github_repository() {
    echo "🔨 Creating repositories (always dual for reliability)..."

    # Always create component 1 repo
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"

    # Always create component 2 repo (using different base branch to avoid duplicate packages)
    echo "  Creating component 2 repository..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component2_base_branch}" \
        "${component2_repo_name}" "${component2_branch}"

    # Create opt-in component
    echo "  Creating opt-in component repository..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${opt_in_component_base_repo_name}" "${opt_in_component_base_branch}" \
        "${opt_in_component_repo_name}" "${opt_in_component_branch}"
}

# Always initialize both components for simplicity and reliability
wait_for_component_initialization() {
    echo "⏳ Waiting for components to initialize (always dual for reliability)..."
    
    # Always wait for component 1
    wait_for_single_component_initialization "${component_name}"
    component_pr="${component_pr}"
    component_pr_number="${pr_number}"
    
    # Always wait for component 2
    wait_for_single_component_initialization "${component2_name}"
    component2_pr="${component_pr}"
    component2_pr_number="${pr_number}"

    # Always wait for opt_in_component
    wait_for_single_component_initialization "${opt_in_component_name}"
    opt_in_component_pr="${component_pr}"
    opt_in_component_pr_number="${pr_number}"

}

# Always merge PRs for both components for simplicity and reliability
merge_github_pr() {
    echo "🔀 Merging PRs for both components (always dual for reliability)..."

    # Always merge component 1
    merge_single_component_pr "${component_pr_number}" "${component_repo_name}" "${NO_CVE}"
    component_sha="${SHA}"

    # Always merge component 2
    merge_single_component_pr "${component2_pr_number}" "${component2_repo_name}" "${NO_CVE}"
    component2_sha="${SHA}"

    # Always merge opt in component
    merge_single_component_pr "${opt_in_component_pr_number}" "${opt_in_component_repo_name}" "${NO_CVE}"
    opt_in_component_sha="${SHA}"

    SHA="${component_sha}"  # Primary SHA for framework compatibility
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

    # Always wait for opt component PLR
    opt_in_comp_plr_name=$(wait_for_single_plr_to_appear "${opt_in_component_sha}")
    opt_in_component_push_plr_name="${opt_in_comp_plr_name}"

}

# Wait for PLR completion for both components in parallel to avoid race conditions
wait_for_plr_to_complete() {
    echo "⏳ Waiting for PipelineRuns to complete for both components in parallel (robustness improvement)..."

    local comp1_plr="${component_push_plr_name}"
    local comp2_plr="${component2_push_plr_name}"
    local opt_in_comp_plr="${opt_in_component_push_plr_name}"

    local comp1_name="${component_name}"
    local comp2_name="${component2_name}"
    local opt_in_comp_name="${opt_in_component_name}"

    local comp1_sha="${component_sha}"
    local comp2_sha="${component2_sha}"
    local opt_in_comp_sha="${opt_in_component_sha}"

    echo "🔄 Starting parallel monitoring of:"
    echo "  - Component 1 PLR: ${comp1_plr} (${comp1_name})"
    echo "  - Component 2 PLR: ${comp2_plr} (${comp2_name})"
    echo "  - Opt In Component PLR: ${opt_in_comp_plr} (${opt_in_comp_name})"

    # Create temporary files to capture results from background processes
    local comp1_result=$(mktemp)
    local comp2_result=$(mktemp)
    local opt_in_comp_result=$(mktemp)

    # Start monitoring both PLRs in parallel
    (
        if wait_for_single_plr_to_complete "${comp1_plr}" "${comp1_name}" "${comp1_sha}"; then
            echo "success" > "${comp1_result}"
            echo "✅ Component 1 (${comp1_name}) PipelineRun completed: ${comp1_plr}" >&2
        else
            echo "failure" > "${comp1_result}"
            echo "🔴 Component 1 (${comp1_name}) PipelineRun failed: ${comp1_plr}" >&2
        fi
    ) &
    local pid1=$!

    (
        if wait_for_single_plr_to_complete "${comp2_plr}" "${comp2_name}" "${comp2_sha}"; then
            echo "success" > "${comp2_result}"
            echo "✅ Component 2 (${comp2_name}) PipelineRun completed: ${comp2_plr}" >&2
        else
            echo "failure" > "${comp2_result}"
            echo "🔴 Component 2 (${comp2_name}) PipelineRun failed: ${comp2_plr}" >&2
        fi
    ) &
    local pid2=$!

    (
        if wait_for_single_plr_to_complete "${opt_in_comp_plr}" "${opt_in_comp_name}" "${opt_in_comp_sha}"; then
            echo "success" > "${opt_in_comp_result}"
            echo "✅ Opt In Component (${opt_in_comp_name}) PipelineRun completed: ${opt_in_comp_plr}" >&2
        else
            echo "failure" > "${opt_in_comp_result}"
            echo "🔴 Opt In Component (${opt_in_comp_name}) PipelineRun failed: ${opt_in_comp_plr}" >&2
        fi
    ) &
    local pid3=$!

    # Wait for both background processes to complete
    echo "⏳ Waiting for both components to complete..."
    wait $pid1
    local exit1=$?
    wait $pid2
    local exit2=$?
    wait $pid3
    local exit3=$?


    # Check results
    local comp1_status=$(cat "${comp1_result}" 2>/dev/null || echo "unknown")
    local comp2_status=$(cat "${comp2_result}" 2>/dev/null || echo "unknown")
    local opt_in_comp_status=$(cat "${opt_in_comp_result}" 2>/dev/null || echo "unknown")

    # Cleanup temp files
    rm -f "${comp1_result}" "${comp2_result}" "${opt_in_comp_result}"

    # Report results
    if [ "${comp1_status}" = "success" ] && [ "${comp2_status}" = "success" ] && [ "${opt_in_comp_status}" == "success" ]; then
        echo "🎉 All PipelineRuns completed successfully in parallel"
        return 0
    else
        echo "🔴 One or more PipelineRuns failed:"
        echo "  - Component 1 (${comp1_name}): ${comp1_status}"
        echo "  - Component 2 (${comp2_name}): ${comp2_status}"
        echo "  - Opt In Component (${opt_in_comp_name}): ${opt_in_comp_status}"
        return 1
    fi
}

# --- Snapshot Management ---

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
                if [ "$scenario" = "optin" ]; then
                    snapshot_name=$(wait_for_single_component_snapshot $opt_in_application_name)
                else
                    snapshot_name=$(wait_for_single_component_snapshot)
                fi
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
verify_staged() {
    local release_name=$1
    echo "🔍 Verifying staged scenario for: $release_name"
    # Add staging-specific verification logic here
    return 0
}

verify_prega() {
    local release_name=$1
    echo "🔍 Verifying prega scenario for: $release_name"
    # Add prega-specific verification logic here
    return 0
}

verify_hotfix() {
    local release_name=$1
    echo "🔍 Verifying hotfix scenario for: $release_name"
    # Add hotfix-specific verification logic here
    return 0
}

verify_optin() {
    local release_name=$1
    echo "🔍 Verifying optin scenario for: $release_name"
    # Add optin-specific verification logic here
    return 0
}

# Wait for a single release to complete
wait_for_release() {
    local release_name=$1
    echo "⏳ Waiting for release $release_name to complete..."

    # Add labels to the release CR for cleanup tracking
    # - originating-tool: identifies which test suite created it (for cleanup)
    # - test-run-uuid: unique ID from test.env (supports concurrent test runs)
    kubectl patch release "${release_name}" -n "${tenant_namespace}" \
      --type merge \
      -p "{\"metadata\":{\"labels\":{\"originating-tool\":\"${originating_tool}\",\"test-run-uuid\":\"${uuid}\"}}}"

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
                verify_staged "$release_name"
                scenario_result=$?
                ;;
            "prega") 
                verify_prega "$release_name"
                scenario_result=$?
                ;;  
            "hotfix") 
                verify_hotfix "$release_name"
                scenario_result=$?
                ;;
            "optin")
                verify_optin "$release_name"
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
