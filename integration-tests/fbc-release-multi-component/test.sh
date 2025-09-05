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
    
    echo "Creating component1 repository ${component1_repo_name} branch ${component1_branch} from ${component_base_repo_name} branch ${component_base_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" "${component_base_repo_name}" "${component_base_branch}" "${component1_repo_name}" "${component1_branch}"
    
    echo "Creating component2 repository ${component2_repo_name} branch ${component2_branch} from ${component_base_repo_name} branch ${component_base_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" "${component_base_repo_name}" "${component_base_branch}" "${component2_repo_name}" "${component2_branch}"
}

# Wait for all components to initialize
wait_for_component_initialization() {
    echo "Waiting for all 2 components to initialize..."
    
    # Component 1
    echo "Waiting for component ${component1_name} in namespace ${tenant_namespace} to be initialized..."
    wait_for_single_component_initialization "${component1_name}"
    component1_pr="${component_pr}"
    component1_pr_number="${pr_number}"
    
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
    echo "Merging PR ${component1_pr_number} in repo ${component1_repo_name}..."
    merge_single_component_pr "${component1_pr_number}" "${component1_repo_name}"
    component1_sha="${SHA}"
    
    # Merge component 2 PR
    echo "Merging PR ${component2_pr_number} in repo ${component2_repo_name}..."
    merge_single_component_pr "${component2_pr_number}" "${component2_repo_name}"
    component2_sha="${SHA}"
    
    # Set the primary SHA for framework compatibility (use component1)
    SHA="${component1_sha}"
    
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
    echo "Waiting for component1 PipelineRun..."
    wait_for_single_plr_to_appear "${component1_sha}"
    component1_push_plr_name="${component_push_plr_name}"
    
    # Wait for component 2 PLR
    echo "Waiting for component2 PipelineRun..."
    wait_for_single_plr_to_appear "${component2_sha}"
    component2_push_plr_name="${component_push_plr_name}"
    
    # Set primary PLR for framework compatibility (use component1)
    component_push_plr_name="${component1_push_plr_name}"
    
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
    
    # Wait for component 1 PLR
    echo "Waiting for component1 PipelineRun ${component1_push_plr_name} to complete..."
    wait_for_single_plr_to_complete "${component1_push_plr_name}" "${component1_name}"
    
    # Wait for component 2 PLR
    echo "Waiting for component2 PipelineRun ${component2_push_plr_name} to complete..."
    wait_for_single_plr_to_complete "${component2_push_plr_name}" "${component2_name}"
    
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
          taskStatus=$(\"${SUITE_DIR}/../scripts/print-taskrun-status.sh\" \"${plr_name}\" \"${tenant_namespace}\" compact)
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
                if [ "${comp_name}" == "${component1_name}" ]; then
                    wait_for_single_plr_to_appear "${component1_sha}"
                    component1_push_plr_name="${component_push_plr_name}"
                    plr_name="${component1_push_plr_name}"
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

      local failures=0
      
      # Check that we have multiple components
      local component_count
      component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")
      echo "Checking component count..."
      if [ "${component_count}" -eq 2 ]; then
        echo "✅️ Found expected 2 components in release"
      else
        echo "🔴 Expected 2 components, found ${component_count}!"
        failures=$((failures+1))
      fi

      # Verify all expected components are present
      echo "Checking component names..."
      local comp1_found comp2_found
      comp1_found=$(jq -r --arg name "${component1_name}" '.status.artifacts.components[] | select(.name == $name) | .name' <<< "${release_json}")
      comp2_found=$(jq -r --arg name "${component2_name}" '.status.artifacts.components[] | select(.name == $name) | .name' <<< "${release_json}")

      if [ "${comp1_found}" = "${component1_name}" ]; then
        echo "✅️ Component 1 found: ${comp1_found}"
      else
        echo "🔴 Component 1 not found: expected ${component1_name}"
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
      comp1_ocp=$(jq -r --arg name "${component1_name}" '.status.artifacts.components[] | select(.name == $name) | .ocp_version' <<< "${release_json}")
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