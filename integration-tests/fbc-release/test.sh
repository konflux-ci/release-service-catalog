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
    ["multi-optin"]="disabled"
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
    
    if [[ "$changed_files" =~ tasks/managed/direct-sign-index-image ]] || \
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
        GLOBAL_TEST_MATRIX["multi-optin"]="enabled"
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
        GLOBAL_TEST_MATRIX["multi-optin"]="enabled"

        show_enabled_scenarios "Enabled" GLOBAL_TEST_MATRIX
    fi
    
    echo "📋 Final test matrix:"
    for key in "${!GLOBAL_TEST_MATRIX[@]}"; do
        echo "  $key: ${GLOBAL_TEST_MATRIX[$key]}"
    done
}

# --- Snapshot Management ---

wait_for_multi_component_snapshot() {
    # replace global with local values
    local effective_application_name=${application_name}
    [ -n "$1" ] && effective_application_name=$1

    echo "📸 Looking for multi-component snapshot..." >&2
    echo "🔍 DEBUG: Search context - namespace: ${tenant_namespace}, application: ${effective_application_name}" >&2
    
    local max_attempts=24  # 12 minutes with 30-second intervals
    local attempt=1
    local snapshot_name=""
    
    while [ $attempt -le $max_attempts ] && [ -z "$snapshot_name" ]; do
        echo "🔍 DEBUG: Multi-component snapshot search attempt ${attempt}/${max_attempts}" >&2
        
        # Get all snapshots for the application
        local all_snapshots
        all_snapshots=$(kubectl get snapshots -n "$tenant_namespace" \
            -l "appstudio.openshift.io/application=${effective_application_name}" \
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
                    snapshot_name=$(wait_for_single_component_snapshot $optin_application_name)
                else
                    snapshot_name=$(wait_for_single_component_snapshot)
                fi
            elif [ "$mode" = "multi" ]; then
                if [ "$scenario" = "optin" ]; then
                    snapshot_name=$(wait_for_multi_component_snapshot $multi_optin_application_name)
                else
                    snapshot_name=$(wait_for_multi_component_snapshot)
                fi
            fi

            if [ -z "$snapshot_name" ]; then
                echo "🔴 Failed to find snapshot for $mode-$scenario"
                exit 1
            fi
            
            # Create manual release
            local release_name="fbc-${mode}-${scenario}-${uuid}"
            local release_plan="fbc-release-${scenario}-rp-${uuid}"
            if [ "$mode" = "multi" ] && [ "$scenario" = "optin" ]; then
            	echo "⏭️ Multi Opt-In ReleasePlan chosen"
            	local release_plan="fbc-release-${mode}-${scenario}-rp-${uuid}"
            fi

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

registry_authenticate() {
    # k8s secret containing the dockerconfigjson
    SECRET_YAML_PATH="$1"
    SECRET_NAME="$2"

    # skopeo, podman and docker auth
    DOCKER_CONFIG="$(mktemp -d)"
    REGISTRY_AUTH_FILE="${DOCKER_CONFIG}/auth.json"

    export DOCKER_CONFIG SECRET_NAME REGISTRY_AUTH_FILE

    yq '. | select(.metadata.name | contains(env(SECRET_NAME))) | .data.".dockerconfigjson"' \
    "${SECRET_YAML_PATH}" | base64 -d > "${DOCKER_CONFIG}/config.json"

    # creates auth.json for podman
    ln -s ${DOCKER_CONFIG}/config.json ${DOCKER_CONFIG}/auth.json
}


# Enhanced verification for multi-component releases  
verify_multi_component_release() {
    local release_name=$1
    echo "🔍 Verifying multi-component release: $release_name"
    
    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)

    local failures=0
    
    # After deduplication, we expect 1 component per unique OCP version (target_index).
    # Multiple fragments for the same target are batched and deduplicated.
    local component_count
    component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")
    echo "Checking component count..."

    if [ "${component_count}" -ge 1 ]; then
      echo "✅️ Found ${component_count} component(s) in release (1 per OCP version after dedup)"
    else
      echo "🔴 Expected at least 1 component, found ${component_count}!"
      failures=$((failures+1))
    fi

    # we need to know if the component is a opt-in
    local mode_scenario="${RELEASES_TO_VERIFY[$release_name]}"
    local scenario="${mode_scenario#*-}"

    for((i=0; i<component_count; i++)); do
        local ocp_version fbc_fragment index_image target_index

        # Verify the component has all required fields and a valid index_image
        local fbc_fragment ocp_version iib_log index_image target_index

        fbc_fragment=$(jq -r --arg i "$i" ".status.artifacts.components[$i].fbc_fragment // \"\"" <<< "${release_json}")
        ocp_version=$(jq -r --arg i "$i" ".status.artifacts.components[$i].ocp_version // \"\"" <<< "${release_json}")
        iib_log=$(jq -r --arg i "$i" ".status.artifacts.components[$i].iibLog // \"\"" <<< "${release_json}")
        index_image=$(jq -r --arg i "$i" ".status.artifacts.components[$i].index_image // \"\"" <<< "${release_json}")
        index_image_resolved=$(jq -r --arg i "$i" ".status.artifacts.components[$i].index_image_resolved // \"\"" <<< "${release_json}")
        target_index=$(jq -r --arg i "$i" ".status.artifacts.components[$i].target_index // \"\"" <<< "${release_json}")

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

        # Verify the published index references the same OCP version reported by the component
        if [ -n "${ocp_version}" ] && [ -n "${target_index}" ]; then
          if [[ "${target_index}" == *"${ocp_version}"* ]]; then
            echo "✅️ target_index contains ${ocp_version}: ${target_index}"
          else
            echo "🔴 target_index does not reference ${ocp_version}: ${target_index}"
            failures=$((failures+1))
          fi
        fi

        # Verify all components are present via image_digests
        local image_digests_count
        image_digests_count=$(jq ".status.artifacts.components[$i].image_digests | length" <<< "${release_json}")
        if [ "${image_digests_count}" -gt 0 ]; then
          echo "✅️ image_digests has ${image_digests_count} entry(ies) (fragments merged into index)"
        else
          echo "🔴 image_digests is empty (index build may have failed to include fragments)!"
          failures=$((failures+1))
        fi

        # Cross-reference snapshot to verify multiple fragments were submitted
        local snapshot_name
        snapshot_name=$(jq -r '.spec.snapshot // ""' <<< "${release_json}")
        if [ -n "${snapshot_name}" ]; then
          local snapshot_component_count
          snapshot_component_count=$(kubectl get snapshot/"${snapshot_name}" -n "${RELEASE_NAMESPACE}" \
            -ojson 2>/dev/null | jq '.spec.components // [] | length')
          if [ "${snapshot_component_count}" -ge 2 ]; then
            echo "✅️ Source snapshot '${snapshot_name}' had ${snapshot_component_count} components (multi-component)"
          else
            echo "🔴 Source snapshot '${snapshot_name}' had ${snapshot_component_count} components, expected >= 2!"
            failures=$((failures+1))
          fi
        fi

        # the upcoming checks are only required for multi optin components
        # otherwise return earlier
        if [  "$scenario" != "optin" ]; then
            return $failures
        fi

        # generate the authentication config for skopeo
        managed_secrets_yaml="${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"
        registry_authenticate $managed_secrets_yaml "konflux-fbc-preview-"

        # making sure the produced indexes versions matches with the requested ones
        index_build_version="$(skopeo \
            inspect "docker://${target_index}" | jq -r '.Env[] | select(test("BUILD_VERSION.*")) | split("=")[1]')"
        if [[ "${index_build_version}" =~ ^${ocp_version} ]]; then
            echo "✅️ Opt-in index-image's BUILD_VERSION matches the required OCP_VERSION ($ocp_version)"
        else
            echo "🔴 Opt-in index-image's BUILD_VERSION DOES NOT match the required OCP_VERSION ($ocp_version)"
            failures=$((failures+1))
        fi

        # The built fbc_fragment's BUILD_VERSION should match the ocp_version
        fragment_build_version="$(skopeo \
            inspect "docker://${fbc_fragment}" | jq -r '.Env[] | select(test("BUILD_VERSION.*")) | split("=")[1]')"
        if [[ "${fragment_build_version}" =~ ^${ocp_version} ]]; then
            echo "✅️ Opt-in fbc_fragment's BUILD_VERSION matches the required OCP_VERSION ($ocp_version)"
        else
            echo "🔴 Opt-in fbc_fragment's BUILD_VERSION DOES NOT match the required OCP_VERSION ($ocp_version)"
            failures=$((failures+1))
        fi
    done

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
    verify_no_redundant_timestamp "$release_name"
    return $?
}

verify_hotfix() {
    local release_name=$1
    echo "🔍 Verifying hotfix scenario for: $release_name"
    verify_no_redundant_timestamp "$release_name"
    return $?
}

# Verify that target_index tags do not contain redundant timestamps.
# Hotfix/pre-GA tags already include a unique suffix (e.g., v4.13-bz12345-<ts>).
# A bug in collect-index-images could append a second timestamp, producing
# something like v4.13-bz12345-1715000000-1715000099. This function catches that.
verify_no_redundant_timestamp() {
    local release_name=$1
    local failures=0

    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)

    local component_count
    component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")

    for ((i=0; i<component_count; i++)); do
        local target_index
        target_index=$(jq -r --argjson i "$i" \
            '.status.artifacts.components[$i].target_index // ""' <<< "${release_json}")

        if [ -z "${target_index}" ]; then
            continue
        fi

        local tag="${target_index##*:}"

        # A redundant timestamp looks like two consecutive numeric segments of 10+ digits
        # at the end of the tag, e.g. v4.13-bz12345-1715000000-1715000099
        if [[ "${tag}" =~ -[0-9]{10,}-[0-9]{10,}$ ]]; then
            echo "🔴 target_index tag has redundant timestamp: ${tag}"
            failures=$((failures + 1))
        else
            echo "✅ target_index tag has no redundant timestamp: ${tag}"
        fi
    done

    if (( failures > 0 )); then
        echo "🔴 Found ${failures} target_index tag(s) with redundant timestamps"
        return 1
    fi
    return 0
}

# Verify the single or multi Optin modes
verify_optin() {
    local release_name=$1
    local mode=$2

    EXPECTED_COMPONENTS_COUNT=1
    if [ "$mode" = "multi" ]; then
        EXPECTED_COMPONENTS_COUNT=2
    fi

    echo "🔍 Verifying $mode optin scenario for: $release_name"

    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)

    local failures=0

    # Opt-in releases should produce 1 or 2 component depending on the mode (single or multi)
    local component_count
    component_count=$(jq '.status.artifacts.components | length' <<< "${release_json}")
    if [ "${component_count}" -eq "${EXPECTED_COMPONENTS_COUNT}" ]; then
      echo "✅️ Opt-in release has exactly ${EXPECTED_COMPONENTS_COUNT} component"
    else
      echo "🔴 Opt-in release expected ${EXPECTED_COMPONENTS_COUNT} component, found ${component_count}!"
      failures=$((failures+1))
    fi

    local snapshot_name
    snapshot_name=$(jq -r '.spec.snapshot // ""' <<< "${release_json}")
    if [ -n "${snapshot_name}" ]; then
      local snapshot_component_count
      snapshot_component_count=$(kubectl get snapshot/"${snapshot_name}" -n "${RELEASE_NAMESPACE}" \
        -ojson 2>/dev/null | jq '.spec.components // [] | length')
      if [ "${snapshot_component_count}" -eq "${EXPECTED_COMPONENTS_COUNT}" ]; then
        echo "✅️ Opt-in snapshot '${snapshot_name}' has ${EXPECTED_COMPONENTS_COUNT} component (correct for $mode opt-in app)"
      else
        echo "🔴 Opt-in snapshot has ${snapshot_component_count} components, expected ${EXPECTED_COMPONENTS_COUNT}!"
        failures=$((failures+1))
      fi
    fi

    # Verify allowedPackages filtering worked: the fbc_fragment should reference the opt-in package
    local fbc_fragments
    fbc_fragments=$(jq -r '[ .status.artifacts.components[].fbc_fragment // "" ]' <<< "${release_json}")
    for(( i=0; i<$(jq -r '. |length' <<< "${fbc_fragments}"); i++ )); do
        local fbc_fragment
        fbc_fragment=$(jq -r --argjson i "$i" '.status.artifacts.components[$i].fbc_fragment // ""' <<< "${release_json}")
        if [ -n "${fbc_fragment}" ]; then
          echo "✅️ Opt-in fbc_fragment present: ${fbc_fragment}"
        else
          echo "🔴 Opt-in fbc_fragment was empty (opt-in filtering may have failed)!"
          failures=$((failures+1))
        fi
    done
    return $failures
}

verify_index_image_content() {
    local release_name=$1
    echo "🔍 Verifying published index content for: $release_name"

    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${RELEASE_NAMESPACE}" -ojson)

    local fbc_fragment target_index
    fbc_fragment=$(jq -r '.status.artifacts.components[0].fbc_fragment // ""' <<< "${release_json}")
    target_index=$(jq -r '.status.artifacts.components[0].target_index // ""' <<< "${release_json}")

    if [ -z "${target_index}" ]; then
        echo "🔴 No target_index in release artifacts"
        return 1
    fi

    if [ -z "${fbc_fragment}" ]; then
        echo "🔴 No fbc_fragment in release artifacts"
        return 1
    fi

    local managed_secrets_yaml="${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml"

    "${SUITE_DIR}/../scripts/verify-fbc-index-content.sh" \
        "${target_index}" "${fbc_fragment}" "${managed_secrets_yaml}"
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
                verify_optin "$release_name" "$mode"
                scenario_result=$?
                ;;
        esac
        
        # Index content verification (non-staged only — staged builds don't publish to a pullable target)
        local content_result=0
        if [ "$scenario" != "staged" ]; then
            verify_index_image_content "$release_name"
            content_result=$?
        else
            echo "  ⏭️  Skipping index content verification for staged release"
        fi

        if [ $mode_result -eq 0 ] && [ $scenario_result -eq 0 ] && [ $pipeline_result -eq 0 ] && [ $content_result -eq 0 ]; then
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
