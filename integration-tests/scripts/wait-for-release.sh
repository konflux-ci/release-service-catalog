#!/usr/bin/env bash
#
# Summary:
#   Monitors a Kubernetes Release custom resource until it reaches a terminal state
#   (Succeeded or Failed). It periodically fetches the Release status, displays
#   a summary of its various processing stages (Tenant Collectors, Managed Collectors,
#   Tenant Pipeline, Managed Pipeline, Final Pipeline), and provides console URLs
#   for associated PipelineRuns. If the Release fails, it attempts to fetch and
#   display logs from the relevant PipelineRuns.
#
# Parameters:
#   None.
#
# Environment Variables:
#   RELEASE_NAME      - The name of the Release custom resource to monitor. Required.
#   RELEASE_NAMESPACE - The Kubernetes namespace where the Release resource exists. Required.
#   CONSOLEURL        - (Derived by the script) The base URL for the OpenShift console,
#                       used to construct links to PipelineRuns and Releases.
#                       It's fetched from the 'pipelines-as-code' ConfigMap.
#   APPLICATION       - (Derived by the script) The name of the application associated
#                       with the Release, extracted from the Release's labels.
#
# Dependencies:
#   kubectl, jq, tkn (for fetching PipelineRun logs).

# Function that identifies a failed Tekton PipelineRun from an input JSON string
# and describes it using 'tkn'.
#
# **Args**:
#   $1 (json): JSON string with '.status.conditions[]' and a field like
#              '.status.<type>Processing.pipelineRun' (e.g. '.status.pipelineProcessing.pipelineRun')
#              containing "namespace/name" of the PipelineRun.
#
# **Deps**: jq, tkn, grep, cut, sed.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function describeFailedPipelineRun() {
  local json=$1
  conditions=$(jq -r '.status.conditions[] | [.type, .status, .reason, .message] | @csv' <<< "${json}")
  echo "${conditions}"

  failedPipelineProcessing=$(grep PipelineProcessed <<< ${conditions} | grep '"False"' | cut -f1 -d, | sed 's/"//g' \
      | sed 's/Pipeline//g' | sed 's/Processed/Processing/' | sed 's/./\L&/')

  ## check if this is a collector pipeline
  ## if so, the status is nested.
  if [[ "${failedPipelineProcessing}" == *"ollector"* ]]; then
    filter=".status.collectorsProcessing.${failedPipelineProcessing}.pipelineRun"
  else
    filter=".status.${failedPipelineProcessing}.pipelineRun"
  fi
  failedPipelineRun=$(jq -r "${filter}" <<< "${json}")

  PLR_NAME=$(cut -f2 -d/ <<< "${failedPipelineRun}")
  PLR_NS=$(cut -f1 -d/ <<< "${failedPipelineRun}")

  diagnoseFailedPLR "${PLR_NAME}" "${PLR_NS}"
}

# Function to diagnose a failed Tekton PipelineRun
# Arguments:
#   $1: PipelineRun name
#   $2: Namespace (optional, defaults to current namespace)
function diagnoseFailedPLR() {
    local plr_name="$1"
    local namespace="${2:-$(kubectl config view --minify -o jsonpath='{..namespace}')}"

    echo "🔍 Diagnosing PipelineRun: ${plr_name} in namespace: ${namespace}"

    # Check if PipelineRun exists
    if [ ! kubectl get pipelinerun "${plr_name}" -n "${namespace}" &>/dev/null ] ; then
        echo "❌ PipelineRun ${plr_name} not found in namespace ${namespace}"
        return 1
    fi

    # Get PipelineRun status
    local status
    status=$(kubectl get pipelinerun "${plr_name}" -n "${namespace}" -o jsonpath='{.status.conditions[0].reason}')
    echo "📊 PipelineRun Status: ${status}"

    # Get all tasks and their statuses
    echo "📋 Task Status Summary:"
    kubectl get pipelinerun "${plr_name}" -n "${namespace}" -o jsonpath='{range .status.taskRuns[*]}{"\n"}Task: {.taskRef.name}{"\nStatus: "}{.status.conditions[0].reason}{"\nMessage: "}{.status.conditions[0].message}{end}' | sed 's/^/  /'

    # Find and show logs for failed tasks
    echo -e "\n❌ Failed Task Details:"
    local failed_tasks
    failed_tasks=$(kubectl get taskruns -l tekton.dev/pipelineRun="${plr_name}" -n "${namespace}" -o jsonpath='{.items[?(@.status.conditions[0].status=="False")].metadata.name}{"\n"}')

    if [ -n "${failed_tasks}" ]; then
        while read -r taskrun_name; do
            echo -e "\n🔍 Examining failed taskrun: ${taskrun_name}"

            if [ -n "${taskrun_name}" ]; then
                echo "📜 Last 50 lines of logs for taskrun ${taskrun_name}:"
                tkn taskrun logs "${taskrun_name}" -n "${namespace}" 2>/dev/null | tail -n 50 | sed 's/^/  /'

                echo -e "\n💡 Describe output:"
                tkn tr desc "${taskrun_name}" -n "${namespace}"

                echo -e "\n💡 Error message:"
                kubectl get taskrun "${taskrun_name}" -n "${namespace}" -o jsonpath='{.status.conditions[0].message}' | sed 's/^/  /'
            else
                echo "⚠️ Could not find TaskRun for task: ${taskrun_name}"
            fi
        done <<< "${failed_tasks}"
    else
        echo "  No failed tasks found. Check overall PipelineRun status and conditions."
    fi

    # Show final conditions and reason for failure
    echo -e "\n📝 Final PipelineRun Conditions:"
    kubectl get pipelinerun "${plr_name}" -n "${namespace}" -o jsonpath='{range .status.conditions[*]}{"\nType: "}{.type}{"\nStatus: "}{.status}{"\nReason: "}{.reason}{"\nMessage: "}{.message}{end}' | sed 's/^/  /'
    echo ""
}

function getPipelinerunFromStatus() { # args are json, statusSection
  json=$1
  statusSection=$2

  filter=".status."$statusSection".pipelineRun"
  PLR=$(jq -r $filter <<< "${json}")
  echo ${PLR//null/}
}

function getConsoleLogForRelease() { # args are application, ns, name
  app=$1
  ns=$2
  name=$3
  releaseUrl="${CONSOLEURL}ns/${ns}/applications/${app}/releases/${name}"
  echo "${releaseUrl}"
}

function getConsoleLogFromPLR() { # args are json, statusSection
  json=$1
  statusSection=$2

  PLR=$(getPipelinerunFromStatus "$json" "$statusSection")

  PLR_NAME=$(cut -f2 -d/ <<< "${PLR}")
  PLR_NS=$(cut -f1 -d/ <<< "${PLR}")
  if [ -z "${PLR_NAME}" ] || [ -z "${PLR_NS}" ]; then
    return
  fi
  prLogUrl="${CONSOLEURL}ns/${PLR_NS}/applications/${APPLICATION}/pipelineruns/${PLR_NAME}"
  echo "${prLogUrl}"
}

function printTaskRunDetails() { # args are pipelineRun, statusReason and optional mode
  PLR_NAME=$(cut -f2 -d/ <<< "$1")
  PLR_NS=$(cut -f1 -d/ <<< "$1")

  # This will print out:
  # Running: 1, Pending: 2, etc.
  mode="${3:-compact}"

  # we only want to print the taskrun details if the status is "Progressing"
  if [ "$2" == "\"Progressing\"" ]; then
    ${SCRIPT_DIR}/print-taskrun-status.sh "${PLR_NAME}" "${PLR_NS}" "${mode}"
  fi

}

function getLogs() { # args are json, statusSection
  json=$1
  statusSection=$2

  PLR=$(getPipelinerunFromStatus "$json" "$statusSection")

  PLR_NAME=$(cut -f2 -d/ <<< "${PLR}")
  PLR_NS=$(cut -f1 -d/ <<< "${PLR}")
  if [ -z "${PLR_NAME}" ] || [ -z "${PLR_NS}" ]; then
    return
  fi
  echo ""
  echo "Getting logs from pipelineRun $PLR"
  echo ""
  /usr/bin/tkn pr logs "${PLR_NAME}" -f --timestamps -n "${PLR_NS}"

  # get console url from kubeconfig using the fact that the Konflux UI uses the same URL
  # pattern as the api service URL.
  consoleUrl=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}" | sed 's/api/konflux-ui.apps/g' | sed 's/:6443//g')
  # get rid of trailing slash
  consoleUrl=${consoleUrl%/}
  prLogUrl="${consoleUrl}/ns/${PLR_NS}/applications/${APPLICATION}/pipelineruns/${PLR_NAME}"

  echo ""
  echo "Console log url: ${prLogUrl}"
  echo ""

}

if [ -z "$RELEASE_NAME" ]; then
  echo "🔴 error: missing env var RELEASE_NAME"
  exit 1
fi
if [ -z "$RELEASE_NAMESPACE" ]; then
  echo "🔴 error: missing env var RELEASE_NAMESPACE"
  exit 1
fi

# Returns 0 if every failing TaskRun in a managed PipelineRun failed due to
# TaskRunImagePullFailed — meaning the failure is purely an infra/registry blip,
# not a real test assertion or pipeline logic error.
is_pure_image_pull_failure() {
  local release_json="$1"

  # Extract managed PLR name and namespace from the Release status
  # .status.managedProcessing.pipelineRun is stored as "namespace/name"
  local plr_namespaced plr_name plr_ns
  plr_namespaced=$(echo "$release_json" | jq -r '.status.managedProcessing.pipelineRun // empty' 2>/dev/null)
  [ -z "$plr_namespaced" ] && return 1
  plr_ns="${plr_namespaced%%/*}"
  plr_name="${plr_namespaced##*/}"
  plr_ns="${plr_ns:-managed-release-team-tenant}"

  [ -z "$plr_name" ] && return 1  # can't determine — assume real failure

  # Collect reasons for all failed TaskRuns in this PLR
  local failed_reasons
  failed_reasons=$(kubectl get taskrun -n "$plr_ns" \
    -l "tekton.dev/pipelineRun=${plr_name}" \
    -o jsonpath='{.items[?(@.status.conditions[0].status=="False")].status.conditions[0].reason}' \
    2>/dev/null)

  [ -z "$failed_reasons" ] && return 1  # no failed tasks found — unexpected, assume real failure

  # If every failure reason is TaskRunImagePullFailed, it's a pure infra issue
  local non_imagepull
  non_imagepull=$(echo "$failed_reasons" | tr ' ' '\n' | grep -v "^TaskRunImagePullFailed$" || true)
  [ -z "$non_imagepull" ]
}

# MAX_RELEASE_RETRIES: how many times to re-create a Release CR when it fails
# due to pure TaskRunImagePullFailed (default 1). Export to override.
RELEASE_RETRIES_LEFT="${MAX_RELEASE_RETRIES:-1}"

# If set, the final effective release name (which may differ from RELEASE_NAME
# when a retry Release CR was created) is written to this file so callers can
# read the correct name for artifact verification.
# Usage: export RELEASE_NAME_OUTPUT_FILE=/tmp/my-release-name
RELEASE_NAME_OUTPUT_FILE="${RELEASE_NAME_OUTPUT_FILE:-}"

CONSOLEURL=$(kubectl get cm/pipelines-as-code -n openshift-pipelines -ojson | jq -r '.data."custom-console-url"')

echo "======================================="
echo "Release           : ${RELEASE_NAME}"
echo "======================================="

RELEASE_JSON=$(kubectl get release/${RELEASE_NAME} -n ${RELEASE_NAMESPACE} -ojson)
RELEASE_NAMESPACE=$(jq -r .metadata.namespace <<< "${RELEASE_JSON}")
APPLICATION=$(jq -r '.metadata.labels."appstudio.openshift.io/application"' <<< "${RELEASE_JSON}")
RELEASE_PLAN=$(jq -r '.spec.releasePlan' <<< "${RELEASE_JSON}")
RELEASE_URL=$(getConsoleLogForRelease "${APPLICATION}" "${RELEASE_NAMESPACE}" "${RELEASE_NAME}")

while true;
do
  RELEASE_JSON=$(kubectl get release/${RELEASE_NAME} -n ${RELEASE_NAMESPACE} -ojson)
  RELEASED=$(jq -r '.status.conditions[] | select(.type=="Released") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  RELEASED_STATUS=$(cut -f1 -d, <<< "${RELEASED}")
  RELEASED_REASON=$(cut -f2 -d, <<< "${RELEASED}")
  RELEASED_MESSAGE=$(cut -f3 -d, <<< "${RELEASED}")

  TENANT_COLLECTOR_PROCESSED=$(jq -r '.status.conditions[] | select(.type=="TenantCollectorsPipelineProcessed") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  TENANT_COLLECTOR_STATUS=$(cut -f1 -d, <<< "${TENANT_COLLECTOR_PROCESSED}")
  TENANT_COLLECTOR_REASON=$(cut -f2 -d, <<< "${TENANT_COLLECTOR_PROCESSED}")
  TENANT_COLLECTOR_MESSAGE=$(cut -f3 -d, <<< "${TENANT_COLLECTOR_PROCESSED}")
  TENANT_COLLECTOR_PIPELINERUN=$(getPipelinerunFromStatus "${RELEASE_JSON}" "collectorsProcessing?.tenantCollectorsProcessing?")
  TENANT_COLLECTOR_PIPELINERUN_URL=$(getConsoleLogFromPLR "${RELEASE_JSON}" "collectorsProcessing?.tenantCollectorsProcessing?")

  TENANT_COLLECTOR_PIPELINERUN_DETAILS=$(printTaskRunDetails "${TENANT_COLLECTOR_PIPELINERUN}" "${TENANT_COLLECTOR_REASON}")

  MANAGED_COLLECTOR_PROCESSED=$(jq -r '.status.conditions[] | select(.type=="ManagedCollectorsPipelineProcessed") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  MANAGED_COLLECTOR_STATUS=$(cut -f1 -d, <<< "${MANAGED_COLLECTOR_PROCESSED}")
  MANAGED_COLLECTOR_REASON=$(cut -f2 -d, <<< "${MANAGED_COLLECTOR_PROCESSED}")
  MANAGED_COLLECTOR_MESSAGE=$(cut -f3 -d, <<< "${MANAGED_COLLECTOR_PROCESSED}")
  MANAGED_COLLECTOR_PIPELINERUN=$(getPipelinerunFromStatus "${RELEASE_JSON}" "collectorsProcessing?.managedCollectorsProcessing?")
  MANAGED_COLLECTOR_PIPELINERUN_URL=$(getConsoleLogFromPLR "${RELEASE_JSON}" "collectorsProcessing?.managedCollectorsProcessing?")

  MANAGED_COLLECTOR_PIPELINERUN_DETAILS=$(printTaskRunDetails "${MANAGED_COLLECTOR_PIPELINERUN}" "${MANAGED_COLLECTOR_REASON}")

  TENANT_PROCESSED=$(jq -r '.status.conditions[] | select(.type=="TenantPipelineProcessed") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  TENANT_STATUS=$(cut -f1 -d, <<< "${TENANT_PROCESSED}")
  TENANT_REASON=$(cut -f2 -d, <<< "${TENANT_PROCESSED}")
  TENANT_MESSAGE=$(cut -f3 -d, <<< "${TENANT_PROCESSED}")
  TENANT_PIPELINERUN=$(getPipelinerunFromStatus "${RELEASE_JSON}" "tenantProcessing?")
  TENANT_PIPELINERUN_URL=$(getConsoleLogFromPLR "${RELEASE_JSON}" "tenantProcessing?")

  TENANT_PIPELINERUN_DETAILS=$(printTaskRunDetails "${TENANT_PIPELINERUN}" "${TENANT_REASON}")

  MANAGED_PROCESSED=$(jq -r '.status.conditions[] | select(.type=="ManagedPipelineProcessed") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  MANAGED_STATUS=$(cut -f1 -d, <<< "${MANAGED_PROCESSED}")
  MANAGED_REASON=$(cut -f2 -d, <<< "${MANAGED_PROCESSED}")
  MANAGED_MESSAGE=$(cut -f3 -d, <<< "${MANAGED_PROCESSED}")
  MANAGED_PIPELINERUN=$(getPipelinerunFromStatus "${RELEASE_JSON}" "managedProcessing?")
  MANAGED_PIPELINERUN_URL=$(getConsoleLogFromPLR "${RELEASE_JSON}" "managedProcessing?")

  MANAGED_PIPELINERUN_DETAILS=$(printTaskRunDetails "${MANAGED_PIPELINERUN}" "${MANAGED_REASON}")

  FINAL_PROCESSED=$(jq -r '.status.conditions[] | select(.type=="FinalPipelineProcessed") | [.status, .reason, .message] | @csv' \
    <<< "${RELEASE_JSON}" )
  FINAL_STATUS=$(cut -f1 -d, <<< "${FINAL_PROCESSED}")
  FINAL_REASON=$(cut -f2 -d, <<< "${FINAL_PROCESSED}")
  FINAL_MESSAGE=$(cut -f3 -d, <<< "${FINAL_PROCESSED}")
  FINAL_PIPELINERUN=$(getPipelinerunFromStatus "${RELEASE_JSON}" "finalProcessing?")
  FINAL_PIPELINERUN_URL=$(getConsoleLogFromPLR "${RELEASE_JSON}" "finalProcessing?")

  FINAL_PIPELINERUN_DETAILS=$(printTaskRunDetails "${FINAL_PIPELINERUN}" "${FINAL_REASON}")

  overAllStatus="Overall Status    : ${RELEASED_REASON} ${RELEASED_MESSAGE} ${RELEASE_NAMESPACE}/${RELEASE_NAME}"
  overAllStatusCount=$(echo "${overAllStatus}" | wc -c)
  overAllStatusLine=
  for ((i = 0 ; i <= ${overAllStatusCount} ; i++)); do
       overAllStatusLine="${overAllStatusLine}-"
  done
  message="
${overAllStatus}
  -> ${RELEASE_URL}
Release Plan      : 📋 ${RELEASE_PLAN}
${overAllStatusLine}
Tenant Collector  : ${TENANT_COLLECTOR_REASON} ${TENANT_COLLECTOR_MESSAGE} ${TENANT_COLLECTOR_PIPELINERUN}
  -> ${TENANT_COLLECTOR_PIPELINERUN_URL}
  ** ${TENANT_COLLECTOR_PIPELINERUN_DETAILS}
Managed Collector : ${MANAGED_COLLECTOR_REASON} ${MANAGED_COLLECTOR_MESSAGE} ${MANAGED_COLLECTOR_PIPELINERUN}
  -> ${MANAGED_COLLECTOR_PIPELINERUN_URL}
  ** ${MANAGED_COLLECTOR_PIPELINERUN_DETAILS}
Tenant            : ${TENANT_REASON} ${TENANT_MESSAGE} ${TENANT_PIPELINERUN}
  -> ${TENANT_PIPELINERUN_URL}
  ** ${TENANT_PIPELINERUN_DETAILS}
Managed           : ${MANAGED_REASON} ${MANAGED_MESSAGE} ${MANAGED_PIPELINERUN}
  -> ${MANAGED_PIPELINERUN_URL}
  ** ${MANAGED_PIPELINERUN_DETAILS}
Final             : ${FINAL_REASON} ${FINAL_MESSAGE} ${FINAL_PIPELINERUN}
  -> ${FINAL_PIPELINERUN_URL}
  ** ${FINAL_PIPELINERUN_DETAILS}
${overAllStatusLine}"

  message=$(sed 's/""//g' <<< "$message")
  message=$(sed 's/->[[:space:]]*$//g' <<< "$message")
  message=$(sed 's/\*\*[[:space:]]*$//g' <<< "$message")
  message=$(sed 's/^.*:[[:space:]]*$//g' <<< "$message")
  message=$(sed '/^[[:space:]]*$/d' <<< "$message")
  message=$(sed 's/"Skipped"/⏭️/g' <<< "$message")
  message=$(sed 's/"Succeeded"/✅️/g' <<< "$message")
  message=$(sed 's/"Progressing"/⏳️/g' <<< "$message")

  if [ "${preMessage}" != "${message}" ]; then
    echo -e "$message"
    echo ""
    preMessage=$message
  fi

  if [ "${RELEASED_STATUS}" == "\"False\"" ] && [ "${RELEASED_REASON}" == "\"Failed\"" ]; then
    RELEASE_JSON=$(kubectl get release/${RELEASE_NAME} -n ${RELEASE_NAMESPACE} -ojson)

    # --- Retry on pure image-pull infra failures ---
    if [ "${RELEASE_RETRIES_LEFT}" -gt 0 ] && is_pure_image_pull_failure "${RELEASE_JSON}"; then
      echo ""
      echo "⚠️  Release ${RELEASE_NAME} failed due to TaskRunImagePullFailed (transient registry issue)."
      local retry_delay="${RELEASE_RETRY_DELAY:-60}"
      echo "   Retrying (${RELEASE_RETRIES_LEFT} attempt(s) left) — waiting ${retry_delay}s for registry to recover..."
      sleep "${retry_delay}"

      local_snapshot=$(jq -r '.spec.snapshot' <<< "${RELEASE_JSON}")
      local_plan=$(jq -r '.spec.releasePlan' <<< "${RELEASE_JSON}")

      # Create a fresh Release CR against the same snapshot + releasePlan
      NEW_RELEASE_NAME=$(kubectl create -f - 2>/dev/null <<EOF | grep -oP '(?<=release\.appstudio\.redhat\.com/)[\w-]+'
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  generateName: retry-
  namespace: ${RELEASE_NAMESPACE}
spec:
  snapshot: ${local_snapshot}
  releasePlan: ${local_plan}
EOF
)
      if [ -z "${NEW_RELEASE_NAME}" ]; then
        echo "🔴 Failed to create retry Release CR — falling through to failure."
      else
        RELEASE_RETRIES_LEFT=$(( RELEASE_RETRIES_LEFT - 1 ))
        RELEASE_NAME="${NEW_RELEASE_NAME}"
        echo "↩️  Monitoring retry Release: ${RELEASE_NAME}"
        echo "======================================="
        echo "Release           : ${RELEASE_NAME}"
        echo "======================================="
        continue
      fi
    fi

    # --- Real failure (not an image pull issue, or retries exhausted) ---
    echo ""
    echo "❌ Error: Release failed!"
    echo ""

    getLogs "${RELEASE_JSON}" "collectorsProcessing?.tenantCollectorsProcessing?"
    getLogs "${RELEASE_JSON}" "collectorsProcessing?.managedCollectorsProcessing?"
    getLogs "${RELEASE_JSON}" "tenantProcessing?"
    getLogs "${RELEASE_JSON}" "managedProcessing?"
    getLogs "${RELEASE_JSON}" "finalProcessing?"

    describeFailedPipelineRun "${RELEASE_JSON}"

    exit 1
  fi

  if [ "${RELEASED_STATUS}" == "\"True\"" ] && [ "${RELEASED_REASON}" == "\"Succeeded\"" ]; then
    echo "✅ Release for ${RELEASE_PLAN} succeeded!"
    [ -n "${RELEASE_NAME_OUTPUT_FILE}" ] && echo "${RELEASE_NAME}" > "${RELEASE_NAME_OUTPUT_FILE}"
    exit 0
  fi
  sleep 5
done
