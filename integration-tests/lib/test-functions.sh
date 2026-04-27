#!/usr/bin/env bash

# --- Function Definitions ---

# Helper function to log errors
log_error() {
    echo "❌ error: $1"
    exit "${2:-1}" # Exit with provided code or 1 by default
}

# Helper function to log errors
log_warning() {
    echo "⚠️ Warning: $1"
}

# Function to check for required environment variables
# depends on global variables: PTSV_COMPONENTS
check_env_vars() {
    echo "Checking required environment variables..."
    local missing_vars=0
    declare -A required_vars=(
        ["GITHUB_TOKEN"]="Missing GITHUB_TOKEN"
        ["VAULT_PASSWORD_FILE"]="Missing VAULT_PASSWORD_FILE"
        ["RELEASE_CATALOG_GIT_URL"]="Missing RELEASE_CATALOG_GIT_URL"
        ["RELEASE_CATALOG_GIT_REVISION"]="Missing RELEASE_CATALOG_GIT_REVISION"
    )

    # Check core required variables
    for var_name in "${!required_vars[@]}"; do
        if [ -z "${!var_name}" ]; then
            echo "❌ error: ${required_vars[$var_name]}"
            missing_vars=$((missing_vars + 1))
        fi
    done

    # Check variables from test.env files (static list of all variables found in test.env files)
    echo "Checking test environment variables..."
    local -a test_env_vars=(
        "application_name"
        "appstudio_component_branch"
        "managed_namespace"
        "managed_sa_name"
        "originating_tool"
        "tenant_namespace"
    )
    for component in ${PTSV_COMPONENTS}; do
        test_env_vars+=("${component}_base_repo_name")
        test_env_vars+=("${component}_base_branch")
        test_env_vars+=("${component}_branch")
        test_env_vars+=("${component}_github_org")
        test_env_vars+=("${component}_git_url")
        test_env_vars+=("${component}_name")
        test_env_vars+=("${component}_repo_name")
        test_env_vars+=("${component}_type")
    done
    for var_name in "${test_env_vars[@]}"; do
        # Check if variable is set
        if [ -z "${!var_name}" ]; then
            echo "❌ error: Missing test environment variable: $var_name"
            missing_vars=$((missing_vars + 1))
        else
            echo "✅ $var_name is set"
        fi
    done

    # Special file validation
    if [ -n "$VAULT_PASSWORD_FILE" ] && [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        echo "❌ error: env var VAULT_PASSWORD_FILE points to a non-existent file: $VAULT_PASSWORD_FILE"
        missing_vars=$((missing_vars + 1))
    fi

    if [ "$missing_vars" -gt 0 ]; then
        log_error "One or more required environment variables are missing or invalid."
    fi

    if [ -n "$KUBECONFIG" ] ; then
      echo "Using provided KUBECONFIG"
    else
      log_warning "KUBECONFIG is not set. Assuming kubectl is configured correctly."
    fi
    echo "Environment variable check complete."
}

# Function to parse script options
# Modifies global variables: CLEANUP, NO_CVE
parse_options() {
    echo "Parsing script options..."
    local opts # Use local for getopt result storage
    opts=$(getopt -l "skip-cleanup,no-cve" -o "sc,nocve" -a -- "$@")
    if [ $? -ne 0 ]; then
        log_error "Failed to parse options."
    fi

    eval set -- "$opts"
    while true; do
        case "$1" in
            -sc|--skip-cleanup)
                CLEANUP="false"
                shift
                ;;
            -nocve|--no-cve)
                NO_CVE="true"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "Internal error in option parsing."
                ;;
        esac
    done
    echo "Options parsed: CLEANUP=${CLEANUP}, NO_CVE=${NO_CVE}"
}

# Function to get Build PipelineRun URL
# Relies on global variables: kubectl (command), jq (command)
get_build_pipeline_run_url() { # args are ns, app, name
  local ns=$1
  local app=$2
  local name=$3
  local console_url

  # get console url from kubeconfig using the fact that the Konflux UI uses the same URL
  # pattern as the api server URL.
  console_url=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}" \
    | sed 's/api/konflux-ui.apps/g' | sed 's/:6443//g')
  # get rid of trailing slash
  console_url=${console_url%/}

  if [ -z "$console_url" ]; then
      log_warning "Could not retrieve custom-console-url. URL might be incomplete."
      echo "kubectl get cm/pipelines-as-code -n openshift-pipelines -ojson" # Add command for easier debugging
      echo "${ns}/applications/${app}/pipelineruns/${name}" # Fallback or partial URL
  else
      echo "${console_url}/ns/${ns}/applications/${app}/pipelineruns/${name}"
  fi
}

# Function for cleaning up resources
# Relies on global variables: CLEANUP, SUITE_DIR, component_repo_name, component_branch, tmpDir, advisory_yaml_dir
# Optional variables: component2_repo_name (for multi-component tests), uuid (from test.env), tenant_namespace
cleanup_resources() {
  local err=${1:-0} # Default to 0 if no error code passed
  local line=${2:-"N/A"}
  local command=${3:-"N/A"}

  if [ "$err" -ne 0 ] ; then
    echo "$0: ERROR: Command '$command' failed at line $line - exited with status $err"
  fi

  if [ "${CLEANUP}" == "true" ]; then
    echo "Performing cleanup..."
    # cleanup...so we can ignore errors
    set +eo pipefail

    local cleanup_log_file
    cleanup_log_file=$(mktemp)
    echo "Cleanup log file: ${cleanup_log_file}"
    echo -e "\n--- Cleanup Log ---" > "${cleanup_log_file}"

    # Clean up component repository
    echo "Deleting Github repository ${component_repo_name} ..." >> "${cleanup_log_file}"
    "${SUITE_DIR}/../scripts/delete-repository.sh" "${component_repo_name}"
    
    # Clean up component2 repository if it exists and is different from component repo
    if [ -n "${component2_repo_name}" ] && [ "${component2_repo_name}" != "${component_repo_name}" ]; then
      echo "Deleting Github repository ${component2_repo_name} ..." >> "${cleanup_log_file}"
      "${SUITE_DIR}/../scripts/delete-repository.sh" "${component2_repo_name}"
    fi

    # Clean up opt_in repository if it exists and is different from component repo
    if [ -n "${opt_in_component_repo_name}" ] && [ "${opt_in_component_repo_name}" != "${component_repo_name}" ]; then
      echo "Deleting Github repository ${opt_in_component_repo_name} ..." >> "${cleanup_log_file}"
      "${SUITE_DIR}/../scripts/delete-repository.sh" "${opt_in_component_repo_name}"
    fi

    if [ -n "$tmpDir" ] && [ -d "$tmpDir" ]; then
        echo "Deleting test resources..." | tee -a "${cleanup_log_file}"
        if [ -f "$tmpDir/tenant-resources.yaml" ]; then
            kubectl delete -f "$tmpDir/tenant-resources.yaml" >> "${cleanup_log_file}" 2>&1
        fi
        if [ -f "$tmpDir/managed-resources.yaml" ]; then
            kubectl delete -f "$tmpDir/managed-resources.yaml" >> "${cleanup_log_file}" 2>&1
        fi
        rm -rf "${tmpDir}"
    else
        echo "tmpDir not set or not a directory, skipping k8s resource cleanup." | tee -a "${cleanup_log_file}"
    fi

    # Clean up Release CRs created by this specific test suite
    # Use both uuid and originating-tool labels to avoid deleting Release CRs
    # belonging to other parallel test suites that share the same uuid
    if [ -n "$uuid" ] && [ -n "$tenant_namespace" ] && [ -n "$originating_tool" ]; then
        echo "Deleting Release CRs with test-run-uuid=${uuid},originating-tool=${originating_tool} in namespace ${tenant_namespace}..." | tee -a "${cleanup_log_file}"
        kubectl delete release -n "${tenant_namespace}" \
            -l "test-run-uuid=${uuid},originating-tool=${originating_tool}" \
            --ignore-not-found >> "${cleanup_log_file}" 2>&1 || \
            echo "Warning: Failed to delete some Release CRs" | tee -a "${cleanup_log_file}"
    else
        echo "Skipping Release CR cleanup: uuid or tenant_namespace not set" | tee -a "${cleanup_log_file}"
    fi

    if [ -n "$advisory_yaml_dir" ] && [ -d "$advisory_yaml_dir" ]; then
        echo "Removing advisory YAML directory..." | tee -a "${cleanup_log_file}"
        rm -rf "${advisory_yaml_dir}" >> "${cleanup_log_file}" 2>&1
    fi
  else
    echo "Skipping cleanup as per --skip-cleanup flag."
  fi

  echo "Killing any child processes..." >> "${cleanup_log_file}"
  pkill -e  -P $$

  if [ "$err" -ne 0 ]; then
    exit "$err"
  fi
}

# Function to decrypt secrets if they don't exist
# Relies on global variable: VAULT_PASSWORD_FILE
# Arguments:
#   $1: location of test suite directory
decrypt_secrets() {
    local suite_dir=$1
    echo "Checking and decrypting secrets..."
    mkdir -p "${suite_dir}/resources/tenant/secrets"
    mkdir -p "${suite_dir}/resources/managed/secrets"

    local tenant_secrets_file="${suite_dir}/resources/tenant/secrets/tenant-secrets.yaml"
    local managed_secrets_file="${suite_dir}/resources/managed/secrets/managed-secrets.yaml"

    if [ ! -f "${tenant_secrets_file}" ]; then
      echo "Tenant secrets missing...decrypting ${suite_dir}/vault/tenant-secrets.yaml"
      ansible-vault decrypt "${suite_dir}/vault/tenant-secrets.yaml" --output "${tenant_secrets_file}" --vault-password-file "$VAULT_PASSWORD_FILE"
    else
      echo "Tenant secrets already exist."
    fi

    if [ ! -f "${managed_secrets_file}" ]; then
      echo "Managed secrets missing...decrypting ${suite_dir}/vault/managed-secrets.yaml"
      ansible-vault decrypt "${suite_dir}/vault/managed-secrets.yaml" --output "${managed_secrets_file}" --vault-password-file "$VAULT_PASSWORD_FILE"
    else
      echo "Managed secrets already exist."
    fi
    echo "Secret decryption check complete."
}
create_github_repositories() {
    echo "🔨 Creating repositories (always dual for reliability)..."
    for component in ${PTSV_COMPONENTS}; do
        local _v="${component}_repo_name"
        local _component_repo_name="${!_v}"
        _v="${component}_branch"
        local _component_branch="${!_v}"
        _v="${component}_base_repo_name"
        local _component_base_repo_name="${!_v}"
        _v="${component}_base_branch"
        local _component_base_branch="${!_v}"

        echo "Creating component repository ${_component_repo_name} branch ${_component_branch} from ${_component_base_repo_name} branch ${_component_base_branch}"
        "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
          "${_component_base_repo_name}" "${_component_base_branch}" \
          "${_component_repo_name}" "${_component_branch}"
    done
}


# Function to set up Kubernetes namespaces
# Relies on global variables: managed_namespace, tenant_namespace
setup_namespaces() {
    echo "Setting up namespaces..."
    set +eo pipefail # Temporarily disable exit on error for checks
    echo "Checking managed namespace: ${managed_namespace}"
    kubectl get ns "${managed_namespace}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      log_error "Managed namespace ${managed_namespace} does not exist." 2
    fi

    echo "Checking tenant namespace: ${tenant_namespace}"
    kubectl get ns "${tenant_namespace}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      log_error "Tenant namespace ${tenant_namespace} does not exist." 2
    fi
    set -eo pipefail # Re-enable exit on error
    kubectl config set-context --current --namespace="$tenant_namespace"
    echo "Namespaces setup complete. Current namespace set to ${tenant_namespace}."
}

# Function to resolve symlinks in a directory for kustomize compatibility
# Kustomize has security restrictions that prevent loading symlinked files
# from outside the kustomization root. This function creates a temporary
# copy with symlinks resolved.
# Arguments:
#   $1: source directory containing potential symlinks
#   $2: destination directory to copy resolved files to
resolve_symlinks_for_kustomize() {
    local src_dir="$1"
    local dest_dir="$2"

    # cp -rL follows symlinks and copies the actual files
    cp -rL "$src_dir" "$dest_dir"
}

# Function to create Kubernetes resources
# Modifies global variable: tmpDir
# Relies on global variables: SUITE_DIR
create_kubernetes_resources() {
    echo "Creating Kubernetes resources..."
    # tmpDir is made global by not declaring it local
    tmpDir=$(mktemp -d)
    echo "Temporary directory for resources: ${tmpDir}"

    # Resolve symlinks in resources directories for kustomize compatibility
    # This allows tests to use symlinks to share resources while maintaining
    # compatibility with kustomize's security restrictions
    echo "Resolving symlinks in resources directories..."
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/tenant" "$tmpDir/tenant"
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/managed" "$tmpDir/managed"

    # Apply infrastructure secrets first (if they exist) - these persist across test runs
    local managed_infra_secrets_file="$tmpDir/managed/secrets/managed-infra-secrets.yaml"
    if [ -f "${managed_infra_secrets_file}" ]; then
        echo "Applying infrastructure secrets (these persist across test runs)..."
        envsubst < "${managed_infra_secrets_file}" > "$tmpDir/managed-infra-resources.yaml"
        kubectl apply -f "$tmpDir/managed-infra-resources.yaml" -n "${managed_namespace}"
    fi

    echo "Building and applying tenant resources..."
    kustomize build "$tmpDir/tenant" | envsubst > "$tmpDir/tenant-resources.yaml"
    kubectl create -f "$tmpDir/tenant-resources.yaml"

    echo "Building and applying managed resources..."
    kustomize build "$tmpDir/managed" | envsubst > "$tmpDir/managed-resources.yaml"
    kubectl apply -f "$tmpDir/managed-resources.yaml"

    echo "Kubernetes resources applied."
}

# Fetch build.appstudio.openshift.io/status from a Component (stdout). Returns 1 if kubectl fails.
# Relies on global variable: tenant_namespace
fetch_component_build_status_annotation() {
    local comp_name="$1"
    local component_json=""
    local kubectl_status=0

    set +e
    component_json=$(kubectl get component/"${comp_name}" -n "${tenant_namespace}" -ojson 2>/dev/null)
    kubectl_status=$?
    set -e

    if [ "${kubectl_status}" -ne 0 ] || [ -z "${component_json}" ]; then
        return 1
    fi

    jq -r --arg k "build.appstudio.openshift.io/status" '.metadata.annotations[$k] // ""' <<< "${component_json}"
}

# Function to wait for component initialization and get PR details
# Modifies global variables: component_pr, pr_number
# Relies on local scope variables: _component_name
# Relies on global variables: tenant_namespace
_wait_for_component_initialization() {
    echo "Waiting for component ${_component_name} in namespace ${tenant_namespace} to be initialized..."

    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=1
    local component_annotations=""
    local initialization_success=false

    while [ $attempt -le $max_attempts ]; do
      echo "Initialization check attempt ${attempt}/${max_attempts}..."

      if ! component_annotations=$(fetch_component_build_status_annotation "${_component_name}"); then
        log_warning "Could not reach component ${_component_name} (kubectl get failed); retrying..."
        if [ $attempt -lt $max_attempts ]; then
          echo "Waiting 10 seconds before retry..."
          sleep 10
        fi
        attempt=$((attempt + 1))
        continue
      fi

      if [ -n "${component_annotations}" ]; then
        # component_pr is made global by not declaring it local
        local component_pr=$(jq -r '.pac."merge-url" // ""' <<< "${component_annotations}")

        if [ -n "${component_pr}" ]; then
            echo "✅ Component initialized successfully"
            initialization_success=true
            local _v="${component}_component_pr"
            echo "Setting $_v=$component_pr"
            declare -g "$_v=$component_pr"
            break
        else
            log_warning "Could not get component PR from annotations: ${component_annotations}"
            echo "Waiting 10 seconds before retry..."
            sleep 10
        fi


      else
        log_warning "Component not yet initialized (attempt ${attempt}/${max_attempts})"

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
      echo "🔴 error: component ${_component_name} failed to initialize after ${max_attempts} attempts ($(($max_attempts * 10 / 60)) minutes)"
      echo "   - Component may not exist in namespace ${tenant_namespace}"
      echo "   - Component creation may have failed"
      exit 1
    fi

    # pr_number is made global by not declaring it local
    local pr_number=$(cut -f7 -d/ <<< "${component_pr}")
    local _v="${component}_pr_number"
    echo "Setting $_v=$pr_number"
    declare -g "$_v=$pr_number"
    if [ -z "${pr_number}" ]; then
        log_error "Could not extract PR number from ${component_pr}"
    fi
    echo "Found PR: ${component_pr} (Number: ${pr_number})"
}

wait_for_components_initialization() {
    for component in $PTSV_COMPONENTS; do
        local _v="${component}_name"
        local _component_name="${!_v}"
        _wait_for_component_initialization # This sets the global variables :
         # ${component}_component_pr and ${component}_pr_number used for merging the PR
    done
}


# Function to merge the GitHub PR
# Modifies global variable: SHA
# Relies on local scope variables: component, _pr_number, _component_repo_name
# Relies on global scope variables: NO_CVE, GITHUB_TOKEN
_merge_github_pr() {
    echo "Merging PR ${_pr_number} in repo ${_component_repo_name}..."
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
        echo "Merge attempt ${attempt}/${max_attempts}..."

        set +e
        merge_result=$(curl -L \
          -X PUT \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $GITHUB_TOKEN" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/repos/${_component_repo_name}/pulls/${_pr_number}/merge" \
          -d "{\"commit_title\":\"e2e test\",\"commit_message\":\"${commit_message}\"}" --silent --show-error --fail-with-body)

        if [ $? -eq 0 ]; then
            success=true
            echo "✅ PR merge succeeded on attempt ${attempt}"
        else
            echo "❌ PR merge failed on attempt ${attempt}. Response: ${merge_result}"
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
        log_error "Failed to merge PR after ${max_attempts} attempts. Last response: ${merge_result}"
    fi

    local SHA=$(jq -r '.sha' <<< "${merge_result}")
    local _v="${component}_SHA"
    echo "Setting $_v=$SHA"
    declare -g "$_v=$SHA"

    if [ -z "$SHA" ] || [ "$SHA" == "null" ]; then
        log_error "Could not get SHA from merge result: ${merge_result}"
    fi
    echo "PR merged. Commit SHA: ${SHA}"
}

merge_github_prs() {
    for component in $PTSV_COMPONENTS; do
        local _v="${component}_repo_name"
        local _component_repo_name="${!_v}"
        _v="${component}_branch"
        local _component_branch="${!_v}"
        _v="${component}_base_repo_name"
        local _component_base_repo="${!_v}"
        _v="${component}_base_branch"
        local _component_base_branch="${!_v}"
        _v="${component}_pr_number"
        local _pr_number="${!_v}"

        _merge_github_pr # This sets the global variable SHA used for waiting for the PipelineRun
    done
}


_get_plr()
{
    local component=$1
    local SHA_VAR="${component}_SHA"
    local SHA="${!SHA_VAR}"
    local _component_push_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$SHA" -n "${tenant_namespace}" --no-headers 2>/dev/null | { grep "Running" || true; } | awk '{print $1}')
    if [ -z "$_component_push_plr_name" ]; then
        return 0
    fi
    echo "$_component_push_plr_name"
}

# Function to wait for a PipelineRun to appear
wait_for_plrs_to_appear() {
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    declare -gA appeared_plrs=()
    local count=$(echo "$PTSV_COMPONENTS" | wc -w)

    echo -n "Waiting for PipelineRun to appear"
    while [ $(echo ${appeared_plrs[@]} | wc -w) -lt $count ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun to appear after ${timeout} seconds"
            exit 1
        fi

        sleep 5
        echo -n "."
        # get only running pipelines
        for component in $PTSV_COMPONENTS; do
            # Only update if we found a PLR and haven't already recorded this component
            if [ -z "${appeared_plrs["$component"]}" ]; then
                local _plr=$(_get_plr "$component")
                appeared_plrs["$component"]="$_plr"
                local _v="${component}_push_plr_name"
                >&2 echo "Setting $_v=$_plr"
                declare -g "$_v=$_plr"
            fi
        done
    done
    echo
    for appeared in "${appeared_plrs[@]}"; do
        echo "✅ Found PipelineRun for component: ${appeared}"
        echo "   PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${appeared}")"
    done
}

# Function to wait for PipelineRuns to complete
# Relies on global variables: ${component}_push_plr_name, tenant_namespace, PTSV_COMPONENTS, appeared_plrs
wait_for_plrs_to_complete() {
    local timeout=1800  # 30 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    declare -A retry_attempted=() # Track retry attempts for each component
    declare -A completed_plrs=() # Track completion status for each component
    local taskStatus="" # taskrun status from last output
    local previousTaskStatus="" # to avoid duplicate output
    local count=$(echo "$PTSV_COMPONENTS" | wc -w)

    for component in $PTSV_COMPONENTS; do
        #local _v="${component}_push_plr_name"
        #local _component_push_plr_name="${!_v}"
        #echo "Waiting for PipelineRun ${_component_push_plr_name} to complete"
        retry_attempted["$component"]="false"
        completed_plrs["$component"]="false"
    done

    while [ ${#completed_plrs[@]} -lt $count ] || [[ " ${completed_plrs[@]} " =~ " false " ]]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun to complete after ${timeout} seconds"
            exit 1
        fi

        sleep 5

        for component in $PTSV_COMPONENTS; do
            # Skip if already completed
            if [ "${completed_plrs["$component"]}" == "true" ]; then
                continue
            fi
            local _v="${component}_push_plr_name"
            local _component_push_plr_name="${!_v}"
            _v="${component}_repo_name"
            local _component_repo_name="${!_v}"
            _v="${component}_name"
            local _component_name="${!_v}"
            _v="${component}_pr_number"
            local _pr_number="${!_v}"
            echo "Component ${component} waiting for PipelineRun ${_component_push_plr_name} to complete"

            # Check if the pipeline run is completed
            local completed=$(kubectl get pipelinerun "${_component_push_plr_name}" -n "${tenant_namespace}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)

            # If completed, check the status
            if [ -n "$completed" ]; then
              taskStatus=$("${SUITE_DIR}/../scripts/print-taskrun-status.sh" "${_component_push_plr_name}" "${tenant_namespace}" compact)
              if [ "${taskStatus}" != "${previousTaskStatus}" ]; then
                echo -e "${taskStatus}"
                previousTaskStatus="${taskStatus}"
              fi
              if [ "$completed" == "True" ]; then
                echo ""
                echo "✅ PipelineRun for component ${_component_name} completed successfully"
                completed_plrs["$component"]="true"
              elif [ "$completed" == "False" ]; then
                echo ""
                echo "❌ PipelineRun for component ${_component_name} failed"
                if [ "${retry_attempted["$component"]}" == "false" ]; then
                    echo "Attempting retry for PR ${_pr_number} in repo ${_component_repo_name}..."
                    kubectl annotate components/${_component_name} build.appstudio.openshift.io/request=trigger-pac-build -n "${tenant_namespace}"
                    appeared_plrs["$component"]="" # Reset to wait for new PLR
                    wait_for_plrs_to_appear
                    retry_attempted["$component"]="true"
                else
                    echo "Retry already attempted. Exiting."
                    exit 1
                fi
              fi
            fi
        done
    done
    for component in $PTSV_COMPONENTS; do
        local _v="${component}_push_plr_name"
        local _component_push_plr_name="${!_v}"
        echo "PipelineRun ${_component_push_plr_name}"
        echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${_component_push_plr_name}")"
    done
}

# Function to diagnose a failed PipelineRun by printing conditions, TaskRun summaries,
# and logs from failed TaskRuns.
# Arguments:
#   $1: PipelineRun name
#   $2: namespace
diagnose_failed_pipelinerun() {
    local plr_name="$1"
    local namespace="$2"

    echo ""
    echo "=== Diagnosing failed PipelineRun: ${plr_name} ==="

    echo "  PipelineRun conditions:"
    kubectl get pipelinerun "${plr_name}" -n "${namespace}" \
        -o jsonpath='{range .status.conditions[*]}    Type={.type}  Status={.status}  Reason={.reason}{"\n"}    Message={.message}{"\n"}{end}' \
        2>/dev/null || true

    echo ""
    echo "  TaskRun summary:"
    kubectl get taskruns -n "${namespace}" \
        -l "tekton.dev/pipelineRun=${plr_name}" \
        -o custom-columns='TASK:.metadata.labels.tekton\.dev/pipelineTask,STATUS:.status.conditions[0].reason,MESSAGE:.status.conditions[0].message' \
        2>/dev/null || true

    echo ""
    local failed_taskruns
    failed_taskruns=$(kubectl get taskruns -n "${namespace}" \
        -l "tekton.dev/pipelineRun=${plr_name}" \
        -o jsonpath='{.items[?(@.status.conditions[0].status=="False")].metadata.name}' \
        2>/dev/null || true)

    if [ -z "${failed_taskruns}" ]; then
        echo "  No individually failed TaskRuns found. Check PipelineRun conditions above."
        return
    fi

    for tr_name in ${failed_taskruns}; do
        local task_label
        task_label=$(kubectl get taskrun "${tr_name}" -n "${namespace}" \
            -o jsonpath='{.metadata.labels.tekton\.dev/pipelineTask}' 2>/dev/null || echo "unknown")

        echo "  --- Failed task: ${task_label} (TaskRun: ${tr_name}) ---"

        local error_msg
        error_msg=$(kubectl get taskrun "${tr_name}" -n "${namespace}" \
            -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || true)
        echo "  Error: ${error_msg}"

        echo "  Logs (last 50 lines):"
        if command -v tkn &>/dev/null; then
            tkn taskrun logs "${tr_name}" -n "${namespace}" 2>/dev/null | tail -50 | sed 's/^/    /' || true
        else
            local pod_name
            pod_name=$(kubectl get taskrun "${tr_name}" -n "${namespace}" \
                -o jsonpath='{.status.podName}' 2>/dev/null || true)
            if [ -n "${pod_name}" ]; then
                kubectl logs "${pod_name}" -n "${namespace}" --all-containers --tail=50 \
                    2>/dev/null | sed 's/^/    /' || true
            fi
        fi
        echo ""
    done
}

# Function to wait for Releases to complete
# Relies on global variables: tenant_namespace, SUITE_DIR
wait_for_releases() {
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local release_names=""
    local all_release_names=""

    for component in $PTSV_COMPONENTS; do
        local _v="${component}_push_plr_name"
        local _component_push_plr_name="${!_v}"
        local _v_rns="${component}_release_names"
        echo -n "Waiting for Releases associated with PLR ${_component_push_plr_name} in namespace ${tenant_namespace}: "
        while [ -z "${!_v_rns}" ]; do
            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))

            if [ $elapsed_time -ge $timeout ]; then
                echo
                echo "🔴 Timeout waiting for Release to appear after ${timeout} seconds"
                exit 1
            fi

            sleep 5
            echo -n "."
            declare -g "$_v_rns=$(kubectl get release \
                -l "appstudio.openshift.io/build-pipelinerun=${_component_push_plr_name}"  \
                -n "${tenant_namespace}" -ojson 2>/dev/null | \
                jq -r '.items[].metadata.name // ""' | xargs)"
        done
    done

    echo ""
    echo "✅ Found: $release_names"

    RUNNING_JOBS="\j" # Bash parameter for number of jobs currently running

    export RELEASE_NAMESPACE=${tenant_namespace}
    for component in $PTSV_COMPONENTS; do
        local _v_rns="${component}_release_names"
        release_names="${!_v_rns}"
        for release in ${release_names};
        do
          # Add labels to the release CR for cleanup tracking
          # - originating-tool: identifies which test suite created it (for periodic cleanup)
          # - test-run-uuid: unique ID from test.env (supports concurrent test runs)
          kubectl patch release "${release}" -n "${tenant_namespace}" \
            --type merge \
            -p "{\"metadata\":{\"labels\":{\"originating-tool\":\"${originating_tool}\",\"test-run-uuid\":\"${uuid}\"}}}"

          all_release_names="${all_release_names} ${release}"
          export RELEASE_NAME=${release}
          "${SUITE_DIR}/../scripts/wait-for-release.sh" &
        done
    done

    # Wait for remaining processes to finish
    while (( ${RUNNING_JOBS@P} > 0 )); do
        wait -n
    done

    export RELEASE_NAMES="$all_release_names"
}

# Function to clean up old resources based on originating tool label
# Arguments:
#   $1: originating_tool label value
#   $2: age in minutes (optional, defaults to 1440 or 24 hours)
cleanup_old_resources() {
    local originating_tool="$1"
    local age_minutes="${2:-1440}"

    if [ -z "$originating_tool" ]; then
        echo "🔴 Error: originating_tool parameter is required"
        return 1
    fi

    # disable exit on error to allow for cleanup of old resources
    set +e
    # Create temporary file and ensure it's cleaned up on exit
    local temp_dir
    temp_dir=$(mktemp -d)
    local old_resources_file="${temp_dir}/old-resources.txt"
    trap 'rm -rf "${temp_dir}"' RETURN

    echo "🔍 Searching for resources with originating-tool=${originating_tool}"

    local kinds="enterprisecontractpolicy rp rpa rolebinding sa clusterrole secret application component imagerepository release"
    for kind in $kinds; do
        local namespaces="dev-release-team-tenant managed-release-team-tenant"
        for namespace in $namespaces; do
            echo "Checking for old resources of kind: $kind in namespace: $namespace"
            kubectl get "$kind" -n "${namespace}" -l originating-tool="${originating_tool}" -o go-template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | \
            awk -v cutoff_time="$(date -d "${age_minutes} minutes ago" +%s)" -v kind=$kind '
            {
                cmd = "date -d " $3 " +%s"
                cmd | getline created_at
                close(cmd)
                if (created_at < cutoff_time) {
                    print "kubectl delete " kind "/" $2 " -n " $1
                }
            }
            ' | tee -a "${old_resources_file}"
        done
    done

    if [ -s "${old_resources_file}" ]; then
        echo "Executing cleanup commands from ${old_resources_file}"
        sh "${old_resources_file}"
    else
        echo "No old resources found to clean up"
    fi
    # re-enable exit on error
    set -e
}

# Function to verify Release contents
verify_release_contents() {
    echo "📝 Note: Test Suite may implement ${FUNCNAME[0]}" \
     "to verify Release contents in their test.sh file"
}

# Function to patch the component source BEFORE Component creation
patch_component_source() {
    echo "📝 Note: Test Suite may implement ${FUNCNAME[0]}" \
     "to patch the component source BEFORE Component creation in their test.sh file"
}

patch_components_source() {
    for component in $PTSV_COMPONENTS; do
        local _v="${component}_name"
        local component_name="${!_v}"
        _v="${component}_repo_name"
        local component_repo_name="${!_v}"
        _v="${component}_pr_number"
        local pr_number="${!_v}"

        echo "Patching component source:"
        echo "  Component: ${component_name}"
        echo "  Repository: ${component_repo_name}"

        patch_component_source
    done
}

# Function to patch the component source BEFORE MERGE
patch_component_source_before_merge() {
    echo "📝 Note: Test Suite may implement ${FUNCNAME[0]}" \
     "to patch the component source BEFORE MERGE in their test.sh file"
}

patch_components_source_before_merge() {
    for component in $PTSV_COMPONENTS; do
        local _v="${component}_name"
        local component_name="${!_v}"
        _v="${component}_repo_name"
        local component_repo_name="${!_v}"
        _v="${component}_pr_number"
        local pr_number="${!_v}"
        echo "Patching component source BEFORE MERGE:"
        echo "  Component: ${component_name}"
        echo "  Repository: ${component_repo_name}"
        echo "  PR Number: ${pr_number}"

        patch_component_source_before_merge
    done
}

# Simple snapshot discovery (no race conditions in controlled test environment)
wait_for_single_component_snapshot() {
    # replace global with local values
    [ -n "$1" ] && application_name=$1

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
