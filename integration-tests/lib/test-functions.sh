#!/usr/bin/env bash

# --- Function Definitions ---

# Helper function to log errors
log_error() {
    echo "❌ error: $1"
    exit "${2:-1}" # Exit with provided code or 1 by default
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

    for var_name in "${!required_vars[@]}"; do
        if [ -z "${!var_name}" ]; then
            echo "❌ error: ${required_vars[$var_name]}"
            missing_vars=$((missing_vars + 1))
        fi
    done

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
      echo "⚠️ Warning: KUBECONFIG is not set. Assuming kubectl is configured correctly."
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
      echo "⚠️ Warning: Could not retrieve custom-console-url. URL might be incomplete."
      echo "kubectl get cm/pipelines-as-code -n openshift-pipelines -ojson" # Add command for easier debugging
      echo "${ns}/applications/${app}/pipelineruns/${name}" # Fallback or partial URL
  else
      echo "${console_url}/ns/${ns}/applications/${app}/pipelineruns/${name}"
  fi
}

# Function for cleaning up resources
# Relies on global variables: CLEANUP, SCRIPT_DIR, component_repo_name, component_branch, tmpDir, advisory_yaml_dir
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

    echo "Deleting Github branch ${component_branch} and PR branch konflux-${component_branch} for repo ${component_repo_name}..." >> "${cleanup_log_file}"
    # Ensure SCRIPT_DIR is available
    "${SCRIPT_DIR}/../scripts/delete-single-branch.sh" "${component_repo_name}" "${component_branch}" >> "${cleanup_log_file}" 2>&1
    "${SCRIPT_DIR}/../scripts/delete-single-branch.sh" "${component_repo_name}" "konflux-${component_branch}" >> "${cleanup_log_file}" 2>&1

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

  if [ "$err" -ne 0 ]; then
    exit "$err"
  fi
}

# Function to decrypt secrets if they don't exist
# Relies on global variables: SCRIPT_DIR, VAULT_PASSWORD_FILE
decrypt_secrets() {
    echo "Checking and decrypting secrets..."
    mkdir -p "${SCRIPT_DIR}/resources/tenant/secrets"
    mkdir -p "${SCRIPT_DIR}/resources/managed/secrets"

    local tenant_secrets_file="${SCRIPT_DIR}/resources/tenant/secrets/tenant-secrets.yaml"
    local managed_secrets_file="${SCRIPT_DIR}/resources/managed/secrets/managed-secrets.yaml"

    if [ ! -f "${tenant_secrets_file}" ]; then
      echo "Tenant secrets missing...decrypting ${SCRIPT_DIR}/vault/tenant-secrets.yaml"
      ansible-vault decrypt "${SCRIPT_DIR}/vault/tenant-secrets.yaml" --output "${tenant_secrets_file}" --vault-password-file "$VAULT_PASSWORD_FILE"
    else
      echo "Tenant secrets already exist."
    fi

    if [ ! -f "${managed_secrets_file}" ]; then
      echo "Managed secrets missing...decrypting ${SCRIPT_DIR}/vault/managed-secrets.yaml"
      ansible-vault decrypt "${SCRIPT_DIR}/vault/managed-secrets.yaml" --output "${managed_secrets_file}" --vault-password-file "$VAULT_PASSWORD_FILE"
    else
      echo "Managed secrets already exist."
    fi
    echo "Secret decryption check complete."
}

# Function to create GitHub branch
# Relies on global variables: SCRIPT_DIR, component_branch, component_base_branch, component_repo_name
create_github_branch() {
    echo "Creating component branch ${component_branch} from ${component_base_branch} in repo ${component_repo_name}..."
    "${SCRIPT_DIR}/../scripts/create-branch-from-base.sh" "${component_repo_name}" "${component_base_branch}" "${component_branch}"
    echo "Branch creation initiated."
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
# Relies on global variables: SCRIPT_DIR
create_kubernetes_resources() {
    echo "Creating Kubernetes resources..."
    # tmpDir is made global by not declaring it local
    tmpDir=$(mktemp -d)
    echo "Temporary directory for resources: ${tmpDir}"

    echo "Building and applying tenant resources..."
    kustomize build "${SCRIPT_DIR}/resources/tenant" | envsubst > "$tmpDir/tenant-resources.yaml"
    kubectl create -f "$tmpDir/tenant-resources.yaml"

    echo "Building and applying managed resources..."
    kustomize build "${SCRIPT_DIR}/resources/managed" | envsubst > "$tmpDir/managed-resources.yaml"
    kubectl create -f "$tmpDir/managed-resources.yaml"

    echo "Kubernetes resources applied."
    echo "Cleanup commands:"
    echo "kubectl delete -f $tmpDir/tenant-resources.yaml"
    echo "kubectl delete -f $tmpDir/managed-resources.yaml"
}

# Function to wait for component initialization and get PR details
# Modifies global variables: component_pr, pr_number
# Relies on global variables: component_name, tenant_namespace
wait_for_component_initialization() {
    echo -n "Waiting for component ${component_name} in namespace ${tenant_namespace} to be initialized: "
    local component_annotations=""
    while [ -z "${component_annotations}" ]; do
      sleep 1
      echo -n "."
      component_annotations=$(kubectl get component/"${component_name}" -n "${tenant_namespace}" -ojson 2>/dev/null | \
        jq -r --arg k "build.appstudio.openshift.io/status" '.metadata.annotations[$k] // ""')
    done
    echo ""
    echo "️✅️ Initialized."

    # component_pr is made global by not declaring it local
    component_pr=$(jq -r '.pac."merge-url" // ""' <<< "${component_annotations}")
    if [ -z "${component_pr}" ]; then
      log_error "Could not get component PR from annotations: ${component_annotations}"
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
    merge_result=$(curl -L \
      -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}/merge" \
      -d "{\"commit_title\":\"e2e test\",\"commit_message\":\"${commit_message}\"}" --silent --show-error --fail-with-body)

    if [ $? -ne 0 ]; then
        log_error "Failed to merge PR. Response: ${merge_result}"
    fi

    # SHA is made global by not declaring it local
    SHA=$(jq -r '.sha' <<< "${merge_result}")
    if [ -z "$SHA" ] || [ "$SHA" == "null" ]; then
        log_error "Could not get SHA from merge result: ${merge_result}"
    fi
    echo "PR merged. Commit SHA: ${SHA}"
}

# Function to wait for Component push PipelineRun to appear
# Modifies global variable: component_push_plr_name
# Relies on global variables: SHA, tenant_namespace, application_name
wait_for_plr_to_appear() {
    echo -n "Waiting for Component push PLR to appear for SHA ${SHA} in namespace ${tenant_namespace}: "
    # component_push_plr_name is made global by not declaring it local
    component_push_plr_name=""
    while [ -z "${component_push_plr_name}" ]; do
      sleep 1
      echo -n "."
      component_push_plr_name=$(kubectl get pr -l "pipelinesascode.tekton.dev/sha=$SHA" -n "${tenant_namespace}" --no-headers 2>/dev/null | awk '{print $1}')
    done
    echo ""
    echo " Found: $component_push_plr_name"
    echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
}

# Function to wait for Component push PipelineRun to complete
# Relies on global variables: component_push_plr_name, tenant_namespace, SCRIPT_DIR, component_repo_name, pr_number, application_name
wait_for_plr_to_complete() {
    echo -n "Waiting for Component push PLR ${component_push_plr_name} in namespace ${tenant_namespace} to complete: "
    local completed=""
    local retry_attempted="false"
    while [ -z "${completed}" ]; do
      sleep 1
      local component_plr_json
      component_plr_json=$(kubectl get pr/"$component_push_plr_name" -n "${tenant_namespace}" -ojson 2>/dev/null)
      if [ -z "$component_plr_json" ]; then
          echo -n "?"
          sleep 4
          continue
      fi

      local component_plr_status
      component_plr_status=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status' <<< "${component_plr_json}")

      if [ "$component_plr_status" == "True" ]; then
        completed="Success"
      elif [ "$component_plr_status" == "False" ]; then
        local component_plr_reason
        component_plr_reason=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .reason' <<< "${component_plr_json}")
        echo ""
        echo "PipelineRun ${component_push_plr_name} reported status False with reason: ${component_plr_reason}"
        /usr/bin/tkn pr logs "$component_push_plr_name" -f --timestamps -n "${tenant_namespace}" || echo "Warning: tkn logs command failed."

        if [ "$component_plr_reason" == "Failed" ] || [ "$component_plr_reason" == "PipelineRunCancelled" ] || [ "$component_plr_reason" == "PipelineRunTimeout" ]; then
          if [ "${retry_attempted}" == "false" ]; then
            echo "Attempting retry for PR ${pr_number} in repo ${component_repo_name}..."
            "${SCRIPT_DIR}/../scripts/add-retry-comment-to-pr.sh" "$component_repo_name" "$pr_number"
            retry_attempted="true"
          else
            echo "Retry already attempted. Exiting."
            echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
            log_error "PipelineRun failed after retry."
          fi
        else
           echo -n "."
        fi
      else
        echo -n "."
      fi
    done
    echo -e "\n✅️ PLR Status: $completed"
    echo "PipelineRun URL: $(get_build_pipeline_run_url "${tenant_namespace}" "${application_name}" "${component_push_plr_name}")"
}

# Function to wait for Release to appear
# Modifies global variables: RELEASE_NAME, RELEASE_NAMESPACE (by exporting)
# Relies on global variables: component_push_plr_name, tenant_namespace, SCRIPT_DIR
wait_for_release() {
    echo -n "Waiting for Release associated with PLR ${component_push_plr_name} in namespace ${tenant_namespace}: "
    # release_name is made global by not declaring it local
    release_name=""
    while [ -z "${release_name}" ]; do
      sleep 5
      echo -n "."
      release_name=$(kubectl get release -l "appstudio.openshift.io/build-pipelinerun=${component_push_plr_name}"  -n "${tenant_namespace}" -ojson 2>/dev/null | jq -r '.items[0].metadata.name // ""')
    done
    echo " Found: $release_name"

    export RELEASE_NAME=${release_name}
    export RELEASE_NAMESPACE=${tenant_namespace}
    "${SCRIPT_DIR}/../scripts/wait-for-release.sh"
}
