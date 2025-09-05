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

# Override framework functions to handle multiple components

# Create GitHub repositories for 2 components
create_github_repository() {
    echo "Creating component repositories for multi-component test..."
    
    echo "Creating component repository ${component_repo_name} branch ${component_branch} from ${component_base_repo_name} branch ${component_base_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" "${component_base_repo_name}" "${component_base_branch}" "${component_repo_name}" "${component_branch}"
    
    echo "Creating component2 repository ${component2_repo_name} branch ${component2_branch} from ${component_base_repo_name} branch ${component_base_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" "${component_base_repo_name}" "${component2_base_branch}" "${component2_repo_name}" "${component2_branch}"
}

# Wait for all components to initialize
wait_for_component_initialization() {
    echo "Waiting for all 2 components to initialize..."
    
    # Component 1
    echo "Waiting for component ${component_name} in namespace ${tenant_namespace} to be initialized..."
    wait_for_single_component_initialization "${component_name}"
    component_pr="${component_pr}"
    component_pr_number="${pr_number}"
    
    # Component 2  
    echo "Waiting for component ${component2_name} in namespace ${tenant_namespace} to be initialized..."
    wait_for_single_component_initialization "${component2_name}"
    component2_pr="${component_pr}"
    component2_pr_number="${pr_number}"
    
    echo "All components initialized successfully"
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

# Merge GitHub PRs for all components
merge_github_pr() {
    echo "Merging PRs for all 2 components..."
    
    # Merge component 1 PR
    echo "Merging PR ${component_pr_number} in repo ${component_repo_name}..."
    merge_single_component_pr "${component_pr_number}" "${component_repo_name}"
    component_sha="${SHA}"
    
    # Merge component 2 PR
    echo "Merging PR ${component2_pr_number} in repo ${component2_repo_name}..."
    merge_single_component_pr "${component2_pr_number}" "${component2_repo_name}"
    component2_sha="${SHA}"
    
    # Set the primary SHA for framework compatibility (use component)
    SHA="${component_sha}"
    
    echo "All PRs merged successfully"
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

# Wait for PipelineRuns to appear for all components
wait_for_plr_to_appear() {
    echo "Waiting for PipelineRuns to appear for all components..."
    
    # Wait for component 1 PLR
    echo "Waiting for component PipelineRun..."
    wait_for_single_plr_to_appear "${component_sha}"
    component_push_plr_name="${component_push_plr_name}"
    
    # Wait for component 2 PLR
    echo "Waiting for component2 PipelineRun..."
    wait_for_single_plr_to_appear "${component2_sha}"
    component2_push_plr_name="${component_push_plr_name}"
    
    # Set primary PLR for framework compatibility (use component)
    # component_push_plr_name is already set from component 1
    
    echo "All PipelineRuns found successfully"
}

# Helper function for single PLR appearance
wait_for_single_plr_to_appear() {
    local sha=$1
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time

    echo -n "Waiting for PipelineRun to appear for SHA ${sha}"
    component_push_plr_name=""
    while [ -z "$component_push_plr_name" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun to appear after ${timeout} seconds for SHA ${sha}"
            exit 1
        fi

        sleep 5
        echo -n "."
        # get only running pipelines
        component_push_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$sha" -n "${tenant_namespace}" --no-headers 2>/dev/null | { grep "Running" || true; } | awk '{print $1}')
    done
    echo
    echo "✅ Found PipelineRun for SHA ${sha}: ${component_push_plr_name}"
    echo "   PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
}

# Wait for PipelineRuns to complete for all components
wait_for_plr_to_complete() {
    echo "Waiting for all PipelineRuns to complete..."
    echo "🔍 DEBUG: Component 1 PLR: ${component_push_plr_name} (${component_name})"
    echo "🔍 DEBUG: Component 2 PLR: ${component2_push_plr_name} (${component2_name})"
    
    # Wait for component 1 PLR
    echo "Waiting for component PipelineRun ${component_push_plr_name} to complete..."
    wait_for_single_plr_to_complete "${component_push_plr_name}" "${component_name}"
    echo "✅ Component 1 (${component_name}) PipelineRun completed: ${component_push_plr_name}"
    
    # Check snapshots after first component completes
    echo "🔍 DEBUG: Checking snapshots after component 1 completion..."
    kubectl get snapshot -n "${tenant_namespace}" -l "appstudio.openshift.io/application=${application_name}" --sort-by=.metadata.creationTimestamp -o json | jq -r '.items[] | "\(.metadata.name) (created: \(.metadata.creationTimestamp), components: \(.spec.components | length))"'
    
    # Wait for component 2 PLR
    echo "Waiting for component2 PipelineRun ${component2_push_plr_name} to complete..."
    wait_for_single_plr_to_complete "${component2_push_plr_name}" "${component2_name}"
    echo "✅ Component 2 (${component2_name}) PipelineRun completed: ${component2_push_plr_name}"
    
    # Check snapshots after second component completes
    echo "🔍 DEBUG: Checking snapshots after component 2 completion..."
    kubectl get snapshot -n "${tenant_namespace}" -l "appstudio.openshift.io/application=${application_name}" --sort-by=.metadata.creationTimestamp -o json | jq -r '.items[] | "\(.metadata.name) (created: \(.metadata.creationTimestamp), components: \(.spec.components | length))"'
    
    # Additional verification - check both PLRs are actually completed
    echo "🔍 DEBUG: Verifying both PipelineRuns are actually completed..."
    local comp1_status comp2_status
    comp1_status=$(kubectl get pipelinerun "${component_push_plr_name}" -n "${tenant_namespace}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)
    comp2_status=$(kubectl get pipelinerun "${component2_push_plr_name}" -n "${tenant_namespace}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)
    
    echo "🔍 DEBUG: Component 1 PLR ${component_push_plr_name} status: ${comp1_status}"
    echo "🔍 DEBUG: Component 2 PLR ${component2_push_plr_name} status: ${comp2_status}"
    
    if [ "$comp1_status" != "True" ] || [ "$comp2_status" != "True" ]; then
        echo "🔴 ERROR: Not all PipelineRuns are successfully completed!"
        echo "   Component 1: ${comp1_status}"
        echo "   Component 2: ${comp2_status}"
        exit 1
    fi
    
    echo "All PipelineRuns completed successfully"
}

# Helper function for single PLR completion
wait_for_single_plr_to_complete() {
    local plr_name=$1
    local comp_name=$2
    local timeout=1800  # 30 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local completed=""
    local retry_attempted="false"
    local taskStatus="" # taskrun status from last output
    local previousTaskStatus="" # to avoid duplicate output

    echo "Waiting for PipelineRun ${plr_name} (${comp_name}) to complete"
    while [ -z "$completed" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun ${plr_name} to complete after ${timeout} seconds"
            exit 1
        fi

        sleep 5

        # Check if the pipeline run is completed
        completed=$(kubectl get pipelinerun "${plr_name}" -n "${tenant_namespace}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)

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
                    plr_name="${component2_push_plr_name}"
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

# Function to manually create releases after both components complete
# This replaces the automatic release creation since auto-release is disabled
create_manual_releases() {
    echo "Creating manual releases for both components after completion..."
    echo "🔍 DEBUG: Expected components:"
    echo "   Component 1: ${component_name}"
    echo "   Component 2: ${component2_name}"
    echo "   Application: ${application_name}"
    echo "   Namespace: ${tenant_namespace}"
    
    # Get the snapshot for the application that contains both components
    local snapshot_name
    local max_attempts=30
    local attempt=1
    
    echo "Looking for snapshot containing both components..."
    
    # First, let's see what snapshots exist
    echo "🔍 DEBUG: All snapshots for application ${application_name}:"
    kubectl get snapshot -n "${tenant_namespace}" -l "appstudio.openshift.io/application=${application_name}" -o json | jq -r '.items[] | "\(.metadata.name) (created: \(.metadata.creationTimestamp))"' | sort
    
    while [ $attempt -le $max_attempts ]; do
        # Get all snapshots sorted by creation time (newest first)
        local snapshots
        snapshots=$(kubectl get snapshot -n "${tenant_namespace}" -l "appstudio.openshift.io/application=${application_name}" --sort-by=.metadata.creationTimestamp -o json)
        
        # Check each snapshot starting from the newest
        local snapshot_count
        snapshot_count=$(echo "$snapshots" | jq '.items | length')
        
        for i in $(seq $((snapshot_count-1)) -1 0); do
            local candidate_snapshot
            candidate_snapshot=$(echo "$snapshots" | jq -r ".items[$i].metadata.name")
            
            echo "Checking snapshot: ${candidate_snapshot}"
            
            # Show all components in this snapshot
            echo "🔍 DEBUG: Components in snapshot ${candidate_snapshot}:"
            kubectl get snapshot "${candidate_snapshot}" -n "${tenant_namespace}" -o json | jq -r '.spec.components[] | "  - \(.name): \(.containerImage)"'
            
            # Check if this snapshot contains both components
            local comp1_found comp2_found
            comp1_found=$(kubectl get snapshot "${candidate_snapshot}" -n "${tenant_namespace}" -o json | jq -r --arg comp "${component_name}" '.spec.components[] | select(.name == $comp) | .name')
            comp2_found=$(kubectl get snapshot "${candidate_snapshot}" -n "${tenant_namespace}" -o json | jq -r --arg comp "${component2_name}" '.spec.components[] | select(.name == $comp) | .name')
            
            echo "🔍 DEBUG: Component matching results:"
            echo "   Looking for component1: '${component_name}' -> found: '${comp1_found:-NONE}'"
            echo "   Looking for component2: '${component2_name}' -> found: '${comp2_found:-NONE}'"
            
            if [ -n "$comp1_found" ] && [ -n "$comp2_found" ]; then
                snapshot_name="$candidate_snapshot"
                echo "✅ Found snapshot with both components: ${snapshot_name}"
                break 2
            else
                echo "⚠️  Snapshot ${candidate_snapshot} missing components: comp1=${comp1_found:-missing}, comp2=${comp2_found:-missing}"
            fi
        done
        
        if [ -z "$snapshot_name" ]; then
            echo "No suitable snapshot found in attempt ${attempt}/${max_attempts}, waiting 10 seconds..."
            sleep 10
            attempt=$((attempt + 1))
        fi
    done
    
    if [ -z "$snapshot_name" ]; then
        echo "🔴 Could not find snapshot containing both components after ${max_attempts} attempts"
        echo "Listing all snapshots for debugging:"
        kubectl get snapshot -n "${tenant_namespace}" -l "appstudio.openshift.io/application=${application_name}"
        exit 1
    fi
    
    echo "Selected snapshot: ${snapshot_name}"
    
    # Debug: Show snapshot contents
    echo "Snapshot contents:"
    kubectl get snapshot "${snapshot_name}" -n "${tenant_namespace}" -o json | jq '.spec.components[] | {name: .name, containerImage: .containerImage}'
    
    # Create releases for each ReleasePlan manually
    local release_plans=("${release_plan_happy_name}" "${release_plan_hotfix_name}" "${release_plan_prega_name}" "${release_plan_staged_name}")
    local created_releases=()
    
    for rp in "${release_plans[@]}"; do
        local release_name="${rp}-$(date +%s)-${RANDOM}"
        echo "Creating release ${release_name} for ReleasePlan ${rp}..."
        
        kubectl create -f - <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${release_name}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
spec:
  releasePlan: ${rp}
  snapshot: ${snapshot_name}
EOF
        
        if [ $? -eq 0 ]; then
            echo "✅ Created release: ${release_name}"
            created_releases+=("${release_name}")
        else
            echo "🔴 Failed to create release for ReleasePlan ${rp}"
            exit 1
        fi
    done
    
    # Wait for releases to complete
    RUNNING_JOBS="\j"
    export RELEASE_NAMESPACE=${tenant_namespace}
    
    for release in "${created_releases[@]}"; do
        export RELEASE_NAME=${release}
        echo "Waiting for release ${release} to complete..."
        "${SUITE_DIR}/../scripts/wait-for-release.sh" &
    done
    
    # Wait for all release jobs to finish
    while (( ${RUNNING_JOBS@P} > 0 )); do
        wait -n
    done
    
    # Export for verification function
    export RELEASE_NAMES="${created_releases[*]}"
    echo "✅ All manual releases completed: ${RELEASE_NAMES}"
}

# Override the framework's wait_for_releases function to use manual release creation
# This ensures both components are built before any releases are created
wait_for_releases() {
    echo "Multi-component test: Using manual release creation after both components complete"
    echo "🔍 DEBUG: Current time: $(date)"
    echo "🔍 DEBUG: About to call create_manual_releases..."
    
    # Add a small delay to ensure any snapshot creation has time to complete
    echo "🔍 DEBUG: Waiting 30 seconds for any final snapshot updates..."
    sleep 30
    
    create_manual_releases
}

# Function to verify Release contents for multi-component FBC with batching
# Relies on global variables: RELEASE_NAMES, RELEASE_NAMESPACE, SCRIPT_DIR, managed_namespace, managed_sa_name, NO_CVE
verify_release_contents() {

    local failed_releases
    for RELEASE_NAME in ${RELEASE_NAMES};
    do
      echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
      local release_json
      release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
      if [ -z "$release_json" ]; then
          log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
      fi

      # DEBUG: Show the actual release JSON structure
      echo "🔍 DEBUG: Full release JSON structure for ${RELEASE_NAME}:"
      echo "$release_json" | jq '.status.artifacts'
      echo ""
      echo "🔍 DEBUG: Components structure:"
      echo "$release_json" | jq '.status.artifacts.components'
      echo ""

      local failures=0
      
      # Check that we have multiple components
      local component_count
      component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")
      echo "Checking component count..."
      echo "🔍 DEBUG: Component count calculation:"
      echo "   Raw components: $(echo "$release_json" | jq '.status.artifacts.components')"
      echo "   Length: ${component_count}"
      
      if [ "${component_count}" -eq 2 ]; then
        echo "✅️ Found expected 2 components in release"
      else
        echo "🔴 Expected 2 components, found ${component_count}!"
        echo "🔍 DEBUG: Let's check if components data is structured differently..."
        echo "   Available keys in artifacts: $(echo "$release_json" | jq -r '.status.artifacts | keys[]')"
        failures=$((failures+1))
      fi

      # Verify all expected components are present
      echo "Checking component names..."
      local comp1_found comp2_found
      comp1_found=$(jq -r --arg name "${component_name}" '.status.artifacts.components[] | select(.name == $name) | .name' <<< "${release_json}")
      comp2_found=$(jq -r --arg name "${component2_name}" '.status.artifacts.components[] | select(.name == $name) | .name' <<< "${release_json}")

      if [ "${comp1_found}" = "${component_name}" ]; then
        echo "✅️ Component 1 found: ${comp1_found}"
      else
        echo "🔴 Component 1 not found: expected ${component_name}"
        failures=$((failures+1))
      fi

      if [ "${comp2_found}" = "${component2_name}" ]; then
        echo "✅️ Component 2 found: ${comp2_found}"
      else
        echo "🔴 Component 2 not found: expected ${component2_name}"
        failures=$((failures+1))
      fi

      # Check that each component has required fields
      for i in $(seq 0 $((component_count-1))); do
        local comp_name fbc_fragment ocp_version iib_log
        comp_name=$(jq -r ".status.artifacts.components[${i}].name // \"\"" <<< "${release_json}")
        fbc_fragment=$(jq -r ".status.artifacts.components[${i}].fbc_fragment // \"\"" <<< "${release_json}")
        ocp_version=$(jq -r ".status.artifacts.components[${i}].ocp_version // \"\"" <<< "${release_json}")
        iib_log=$(jq -r ".status.artifacts.components[${i}].iibLog // \"\"" <<< "${release_json}")

        echo "Verifying component ${comp_name} (index ${i})..."
        
        if [ -n "${fbc_fragment}" ]; then
          echo "✅️ Component ${comp_name} fbc_fragment: ${fbc_fragment}"
        else
          echo "🔴 Component ${comp_name} fbc_fragment was empty!"
          failures=$((failures+1))
        fi

        if [ -n "${ocp_version}" ]; then
          echo "✅️ Component ${comp_name} ocp_version: ${ocp_version}"
        else
          echo "🔴 Component ${comp_name} ocp_version was empty!"
          failures=$((failures+1))
        fi

        if [ -n "${iib_log}" ]; then
          echo "✅️ Component ${comp_name} iib_log: ${iib_log}"
        else
          echo "🔴 Component ${comp_name} iib_log was empty!"
          failures=$((failures+1))
        fi
      done

      # Verify batching behavior by checking OCP versions
      echo "Verifying batching scenarios..."
      local comp1_ocp comp2_ocp
      comp1_ocp=$(jq -r --arg name "${component_name}" '.status.artifacts.components[] | select(.name == $name) | .ocp_version' <<< "${release_json}")
      comp2_ocp=$(jq -r --arg name "${component2_name}" '.status.artifacts.components[] | select(.name == $name) | .ocp_version' <<< "${release_json}")

      if [ "${comp1_ocp}" = "v4.13" ] && [ "${comp2_ocp}" = "v4.13" ]; then
        echo "✅️ Components 1 & 2 both have v4.13 (expected to be batched together)"
      else
        echo "🔴 Components 1 & 2 OCP versions mismatch: comp1=${comp1_ocp}, comp2=${comp2_ocp}"
        failures=$((failures+1))
      fi

      # Check index_image fields
      local index_image index_image_resolved
      index_image=$(jq -r '.status.artifacts.index_image.index_image // ""' <<< "${release_json}")
      index_image_resolved=$(jq -r '.status.artifacts.index_image.index_image_resolved // ""' <<< "${release_json}")

      echo "Checking index_image..."
      if [ -n "${index_image}" ]; then
        echo "✅️ index_image: ${index_image}"
      else
        echo "🔴 index_image was empty!"
        failures=$((failures+1))
      fi
      echo "Checking index_image_resolved..."
      if [ -n "${index_image_resolved}" ]; then
        echo "✅️ index_image_resolved: ${index_image_resolved}"
      else
        echo "🔴 index_image_resolved was empty!"
        failures=$((failures+1))
      fi

      if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        failed_releases="${RELEASE_NAME} ${failed_releases}"
      else
        echo "✅️ All multi-component release checks passed. Success!"
      fi
    done

    if [ -n "${failed_releases}" ]; then
      echo "🔴 Releases FAILED: ${failed_releases}"
      exit 1
    else
      echo "✅️ Multi-component FBC release test SUCCESS!"
    fi
}