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
        "component_github_org"
        "appstudio_component_branch"
        "component_base_repo_name"
        "component_base_branch"
        "component_branch"
        "component_git_url"
        "component_name"
        "component_repo_name"
        "component_type"
        "managed_namespace"
        "managed_sa_name"
        "originating_tool"
        "tenant_namespace"
    )
    for var_name in "${test_env_vars[@]}"; do
        # Check if variable is set
        if [ -z "${!var_name}" ]; then
            echo "❌ error: Missing test environment variable: $var_name"
            missing_vars=$((missing_vars + 1))
        else
            echo "✅ $var_name is set"
        fi
    done

    # Check for optional component2 variables (for multi-component tests)
    local optional_component2_vars=(
        "component2_name"
        "component2_branch"
        "component2_repo_name"
        "component2_git_url"
    )
    
    for var_name in "${optional_component2_vars[@]}"; do
        if [ -n "${!var_name}" ]; then
            echo "✅ $var_name is set (optional multi-component variable)"
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
# Optional variables: component2_repo_name (for multi-component tests)
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

create_github_repository() {
    echo "Creating component repository ${component_repo_name} branch ${component_branch} from ${component_base_repo_name} branch ${component_base_branch}"
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" "${component_base_repo_name}" "${component_base_branch}" "${component_repo_name}" "${component_branch}"
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

# Function to create Kubernetes resources
# Modifies global variable: tmpDir
# Relies on global variables: SUITE_DIR
create_kubernetes_resources() {
    echo "Creating Kubernetes resources..."
    # tmpDir is made global by not declaring it local
    tmpDir=$(mktemp -d)
    echo "Temporary directory for resources: ${tmpDir}"

    echo "Building and applying tenant resources..."
    kustomize build "${SUITE_DIR}/resources/tenant" | envsubst > "$tmpDir/tenant-resources.yaml"
    kubectl create -f "$tmpDir/tenant-resources.yaml"

    echo "Building and applying managed resources..."
    kustomize build "${SUITE_DIR}/resources/managed" | envsubst > "$tmpDir/managed-resources.yaml"
    # use "kubectl apply" to avoid failure when a secret already exists 
    # since some secret name is hardcoded in the task, it may conflict when several tests run in parellel. 
    kubectl apply -f "$tmpDir/managed-resources.yaml"

    echo "Kubernetes resources applied."
}

# Function to wait for component initialization and get PR details
# Modifies global variables: component_pr, pr_number
# Relies on global variables: component_name, tenant_namespace
wait_for_component_initialization() {
    echo "Waiting for component ${component_name} in namespace ${tenant_namespace} to be initialized..."

    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=1
    local component_annotations=""
    local initialization_success=false

    while [ $attempt -le $max_attempts ]; do
      echo "Initialization check attempt ${attempt}/${max_attempts}..."

      # Try to get component annotations
      component_annotations=$(kubectl get component/"${component_name}" -n "${tenant_namespace}" -ojson 2>/dev/null | \
        jq -r --arg k "build.appstudio.openshift.io/status" '.metadata.annotations[$k] // ""')

      if [ -n "${component_annotations}" ]; then
        # component_pr is made global by not declaring it local
        component_pr=$(jq -r '.pac."merge-url" // ""' <<< "${component_annotations}")
        if [ -n "${component_pr}" ]; then
            echo "✅ Component initialized successfully"
            initialization_success=true
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
      echo "🔴 error: component ${component_name} failed to initialize after ${max_attempts} attempts ($(($max_attempts * 10 / 60)) minutes)"
      echo "   - Component may not exist in namespace ${tenant_namespace}"
      echo "   - Component creation may have failed"
      exit 1
    fi

    # pr_number is made global by not declaring it local
    pr_number=$(cut -f7 -d/ <<< "${component_pr}")
    if [ -z "${pr_number}" ]; then
        log_error "Could not extract PR number from ${component_pr}"
    fi
    echo "Found PR: ${component_pr} (Number: ${pr_number})"
}

# Function to merge the GitHub PR
# Modifies global variable: SHA
# Relies on global variables: pr_number, component_repo_name, NO_CVE, GITHUB_TOKEN
merge_github_pr() {
    echo "Merging PR ${pr_number} in repo ${component_repo_name}..."
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
          "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}/merge" \
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

    # SHA is made global by not declaring it local
    SHA=$(jq -r '.sha' <<< "${merge_result}")
    if [ -z "$SHA" ] || [ "$SHA" == "null" ]; then
        log_error "Could not get SHA from merge result: ${merge_result}"
    fi
    echo "PR merged. Commit SHA: ${SHA}"
}

# Function to wait for a PipelineRun to appear
# Sets global variable: component_push_plr_name
wait_for_plr_to_appear() {
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time

    echo -n "Waiting for PipelineRun to appear"
    component_push_plr_name=""
    while [ -z "$component_push_plr_name" ]; do
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
        component_push_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$SHA" -n "${tenant_namespace}" --no-headers 2>/dev/null | { grep "Running" || true; } | awk '{print $1}')
    done
    echo
    echo "✅ Found PipelineRun: ${component_push_plr_name}"
    echo "   PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
}

# Function to wait for PipelineRun to complete
# Relies on global variables: component_push_plr_name, tenant_namespace
wait_for_plr_to_complete() {
    local timeout=1800  # 30 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local completed=""
    local retry_attempted="false"
    local taskStatus="" # taskrun status from last output
    local previousTaskStatus="" # to avoid duplicate output

    echo "Waiting for PipelineRun ${component_push_plr_name} to complete"
    while [ -z "$completed" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo
            echo "🔴 Timeout waiting for PipelineRun to complete after ${timeout} seconds"
            exit 1
        fi

        sleep 5

        # Check if the pipeline run is completed
        completed=$(kubectl get pipelinerun "${component_push_plr_name}" -n "${tenant_namespace}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)

        # If completed, check the status
        if [ -n "$completed" ]; then
          taskStatus=$("${SUITE_DIR}/../scripts/print-taskrun-status.sh" "${component_push_plr_name}" "${tenant_namespace}" compact)
          if [ "${taskStatus}" != "${previousTaskStatus}" ]; then
            echo -e "${taskStatus}"
            previousTaskStatus="${taskStatus}"
          fi
          if [ "$completed" == "True" ]; then
            echo ""
            echo "✅ PipelineRun completed successfully"
            break
          elif [ "$completed" == "False" ]; then
            echo ""
            echo "❌ PipelineRun failed"
            if [ "${retry_attempted}" == "false" ]; then
                echo "Attempting retry for PR ${pr_number} in repo ${component_repo_name}..."
                kubectl annotate components/${component_name} build.appstudio.openshift.io/request=trigger-pac-build -n "${tenant_namespace}"
                wait_for_plr_to_appear # component_push_plr_name is set here
                retry_attempted="true"
            else
                echo "Retry already attempted. Exiting."
                exit 1
            fi
          fi
          completed=""
        fi
    done
    echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
}

# Function to wait for Releases to complete
# Relies on global variables: component_push_plr_name, tenant_namespace, SUITE_DIR
wait_for_releases() {
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local release_names=""

    echo -n "Waiting for Releases associated with PLR ${component_push_plr_name} in namespace ${tenant_namespace}: "
    while [ -z "${release_names}" ]; do
      current_time=$(date +%s)
      elapsed_time=$((current_time - start_time))

      if [ $elapsed_time -ge $timeout ]; then
          echo
          echo "🔴 Timeout waiting for Release to appear after ${timeout} seconds"
          exit 1
      fi

      sleep 5
      echo -n "."
      release_names=$(kubectl get release -l "appstudio.openshift.io/build-pipelinerun=${component_push_plr_name}"  \
        -n "${tenant_namespace}" -ojson 2>/dev/null | jq -r '.items[].metadata.name // ""' | xargs)
    done
    echo ""
    echo "✅ Found: $release_names"

    RUNNING_JOBS="\j" # Bash parameter for number of jobs currently running

    export RELEASE_NAMESPACE=${tenant_namespace}
    for release in ${release_names};
    do
      export RELEASE_NAME=${release}
      "${SUITE_DIR}/../scripts/wait-for-release.sh" &
    done

    # Wait for remaining processes to finish
    while (( ${RUNNING_JOBS@P} > 0 )); do
        wait -n
    done

    export RELEASE_NAMES="$release_names"
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

    local kinds="enterprisecontractpolicy rp rpa rolebinding sa clusterrole secret application component"
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

# Function to patch the component source BEFORE MERGE
patch_component_source_before_merge() {
    echo "📝 Note: Test Suite may implement ${FUNCNAME[0]}" \
     "to patch the component source BEFORE MERGE in their test.sh file"
}
