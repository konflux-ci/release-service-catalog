#!/usr/bin/env bash

#
# Summary:
#   Fetches the content of an advisory OCI (Open Container Initiative) artifact.
#   It achieves this by creating a Tekton PipelineRun in a specified Kubernetes
#   managed namespace. The PipelineRun uses a predefined pipeline from a release-service-catalog
#   to retrieve the artifact based on an advisory URL. The script then waits for
#   the PipelineRun to complete and extracts the artifact content to a specified output directory.
#
# Parameters:
#   $1: managed_namespace   - The Kubernetes namespace where the PipelineRun will be created
#                             and executed.
#   $2: managed_sa_name     - The name of the Kubernetes ServiceAccount to be used by
#                             the PipelineRun in the managed_namespace.
#   $3: advisory_url        - The URL of the advisory OCI artifact to fetch.
#   $4: output_dir          - The local directory where the fetched artifact content
#                             will be extracted.
#
# Environment Variables:
#   KUBECONFIG (optional)                 - Path to the kubeconfig file. If not set,
#                                           kubectl's default configuration is used.
#   RELEASE_CATALOG_GIT_URL (optional)    - The Git URL for the release service catalog
#                                           containing the Tekton task.
#                                           Defaults to "https://github.com/konflux-ci/release-service-catalog.git".
#   RELEASE_CATALOG_GIT_REVISION (optional) - The Git revision (branch, tag, or commit SHA)
#                                           of the release service catalog to use.
#                                           Defaults to "development".
#
# Dependencies:
#   kubectl, jq, mktemp, uuidgen (or a command that provides similar functionality like 'uuid'),
#   oras (for fetching OCI artifacts), tkn (optional, for displaying PipelineRun logs, fallback provided).

set -eo pipefail

# Function to print error messages and exit
error_exit() {
  echo "🔴 error: $1" >&2
  exit 1
}

# Function to validate script parameters
validate_params() {
  managed_namespace=$1
  managed_sa_name=$2
  advisory_url=$3
  output_dir=$4

  if [ -z "$managed_namespace" ]; then
    error_exit "missing parameter managed_namespace"
  fi
  if [ -z "$managed_sa_name" ]; then
    error_exit "missing parameter managed_sa_name"
  fi
  if [ -z "$advisory_url" ]; then
    error_exit "missing parameter advisory_url"
  fi
  if [ -z "$output_dir" ]; then
    error_exit "missing parameter output_dir"
  fi

  echo "managed_namespace: ${managed_namespace}"
  echo "advisory_url: ${advisory_url}"
  echo "output_dir: ${output_dir}"
}

# Function to set up environment variables and configurations
setup_env() {
  if [ -n "$KUBECONFIG" ]; then
    echo "Using provided KUBECONFIG"
  fi

  if [ -n "$RELEASE_CATALOG_GIT_URL" ]; then
    echo "Using provided RELEASE_CATALOG_GIT_URL: ${RELEASE_CATALOG_GIT_URL}"
  else
    RELEASE_CATALOG_GIT_URL="https://github.com/konflux-ci/release-service-catalog.git"
    echo "Defaulting to RELEASE_CATALOG_GIT_URL: ${RELEASE_CATALOG_GIT_URL}"
  fi
  export RELEASE_CATALOG_GIT_URL # Export to make it available to sub-processes if needed

  if [ -n "$RELEASE_CATALOG_GIT_REVISION" ]; then
    echo "Using provided RELEASE_CATALOG_GIT_REVISION: ${RELEASE_CATALOG_GIT_REVISION}"
  else
    RELEASE_CATALOG_GIT_REVISION="development"
    echo "Defaulting to RELEASE_CATALOG_GIT_REVISION: ${RELEASE_CATALOG_GIT_REVISION}"
  fi
  export RELEASE_CATALOG_GIT_REVISION # Export to make it available

  kubectl config set-context --current --namespace="${managed_namespace}"
}

# Function to create and apply PipelineRun YAML
create_and_apply_pipelinerun() {
  local managed_sa_name_param=$1
  local advisory_url_param=$2
  local pipelinerun_label_param=$3
  local uuid_param=$4

  local pipelinerunYaml
  pipelinerunYaml=$(mktemp)
  cat > "${pipelinerunYaml}" << EOF
---
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: request-advisory-oci-artifact-
  labels:
    ${pipelinerun_label_param}: ${uuid_param}
spec:
  taskRunTemplate:
    serviceAccountName: ${managed_sa_name_param}
  params:
    - name: advisory_url
      value: ${advisory_url_param}
    - name: taskGitUrl
      value: ${RELEASE_CATALOG_GIT_URL}
    - name: taskGitRevision
      value: ${RELEASE_CATALOG_GIT_REVISION}
  pipelineRef:
    resolver: "git"
    params:
      - name: url
        value: ${RELEASE_CATALOG_GIT_URL}
      - name: revision
        value: ${RELEASE_CATALOG_GIT_REVISION}
      - name: pathInRepo
        value: pipelines/internal/request-advisory-oci-artifact/request-advisory-oci-artifact.yaml
EOF

  kubectl create -f "${pipelinerunYaml}" > /dev/null 2> /dev/null
  rm "${pipelinerunYaml}" # Clean up temp file

  # Return the PipelineRun name
  kubectl get pr -l "${pipelinerun_label_param}=${uuid_param}" -n "${managed_namespace}" --no-headers 2> /dev/null | awk '{print $1}'
}

# Function to wait for PipelineRun completion
wait_for_pipelinerun() {
  local pipelinerun_name_param=$1
  local managed_namespace_param=$2

  echo ""
  echo -n "Waiting for PipelineRun '${pipelinerun_name_param}' to complete: "
  local completed=""
  while [ -z "${completed}" ]; do
    sleep 1
    local plr_json
    plr_json=$(kubectl get "pr/${pipelinerun_name_param}" -n "${managed_namespace_param}" -ojson 2>/dev/null || true)
    if [ -z "$plr_json" ]; then
        echo -n "?" # PipelineRun not found yet or disappeared
        continue
    fi

    local plr_status
    plr_status=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status' <<< "${plr_json}")

    if [ "$plr_status" == "True" ]; then
      completed="Success"
    elif [ "$plr_status" == "False" ]; then
      local plr_reason
      plr_reason=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .reason' <<< "${plr_json}")
      if [ "$plr_reason" == "Failed" ] || [ "$plr_reason" == "PipelineValidationFailed" ] || [ "$plr_reason" == "InvalidPipelineResultReference" ] ; then # Added more failure reasons
        echo ""
        echo "🔴 FAILED. Reason: ${plr_reason}. See logs:"
        # Using 'tkn' if available, otherwise fallback or just suggest kubectl logs
        if command -v tkn &> /dev/null; then
            tkn pr logs "$pipelinerun_name_param" -f --timestamps -n "${managed_namespace_param}"
        else
            echo "tkn command not found. Use 'kubectl logs -n ${managed_namespace_param} -f pod/<pod-name-associated-with-pipelinerun-${pipelinerun_name_param}>' to check logs."
        fi
        exit 1 # Exit directly from the function, or return a status and check in main
      else
        echo -n "." # Still progressing or unknown transient error
      fi
    else
      echo -n "." # Still progressing
    fi
  done
  echo ""
  echo "$completed"
}

# Function to fetch and extract OCI artifact
fetch_and_extract_artifact() {
  local pipelinerun_name_param=$1
  local managed_namespace_param=$2
  local output_dir_param=$3

  local uri
  uri=$(kubectl get "pr/${pipelinerun_name_param}" -n "${managed_namespace_param}" -ojson | jq -r '.status.results[]? | select(.name == "advisory-oci-artifact") | .value')

  if [ -z "$uri" ] || [ "$uri" == "null" ]; then
      error_exit "Could not retrieve advisory-oci-artifact URI from PipelineRun ${pipelinerun_name_param}"
  fi

  local oci_artifact="${uri#*:}" # Assuming the URI might have a scheme like "oci:"

  echo "oci_artifact: ${oci_artifact}"

  if ! command -v oras &> /dev/null; then
    error_exit "oras command not found. Please install oras to fetch the artifact."
  fi

  oras blob fetch "${oci_artifact}" --output - | tar -C "${output_dir_param}" --no-overwrite-dir -zxmf -
  echo "✅️ Restored artifact ${oci_artifact} to ${output_dir_param}"
}

# Main execution
main() {
  # Ensure all parameters are passed
  if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <managed_namespace> <managed_sa_name> <advisory_url> <output_dir>"
    exit 1
  fi

  # Assign parameters to global variables (or pass them explicitly to functions)
  # For simplicity in this refactor, using global variables for some, but passing is cleaner
  managed_namespace=$1
  managed_sa_name=$2
  advisory_url=$3
  output_dir=$4

  validate_params "$managed_namespace" "$managed_sa_name" "$advisory_url" "$output_dir"
  setup_env # Relies on managed_namespace being set

  local pipelinerun_label="internal-services.appstudio.openshift.io/pipelinerun-uid"
  local uuid
  uuid=$(uuidgen) # Using uuidgen for better compatibility if 'uuid' command isn't 'uuidgen'

  local pipelinerun_name
  pipelinerun_name=$(create_and_apply_pipelinerun "$managed_sa_name" "$advisory_url" "$pipelinerun_label" "$uuid")

  if [ -z "$pipelinerun_name" ]; then
      error_exit "Failed to create or find PipelineRun."
  fi
  echo "✅️ Found PipelineRun: ${pipelinerun_name}"

  wait_for_pipelinerun "$pipelinerun_name" "$managed_namespace"
  fetch_and_extract_artifact "$pipelinerun_name" "$managed_namespace" "$output_dir"

  echo "✅️ Script completed successfully."
}

# Call the main function with all script arguments
main "$@"
