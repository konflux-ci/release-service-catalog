#!/bin/bash

# This script will run task tests for all task directories
# provided either via TEST_ITEMS env var, or as arguments
# when running the script.
#
# Requirements:
# - Connection to a running k8s cluster (e.g. kind)
# - Tekton installed on the cluster
# - tkn installed
#

# yield empty strings for unmatched patterns
shopt -s nullglob

WORKSPACE_TEMPLATE=${BASH_SOURCE%/*/*}/resources/workspace-template.yaml

show_help() {
  echo "Usage: $0 [--remove-compute-resources] [item1] [item2] [...]"
  echo
  echo Flags:
  echo "  --help: Show this help message"
  echo "  --remove-compute-resources: Remove compute resources from tasks"
  echo
  echo "Items can be task directories or paths to task test yaml files"
  echo "(useful when working on a single test). They can be supplied"
  echo "either as arguments or via the TEST_ITEMS environment variable."
  echo
  echo "Examples:"
  echo "  $0 --remove-compute-resources tasks/apply-mapping"
  echo "  $0 tasks/apply-mapping/tests/test-apply-mapping.yaml"
  exit 1
}

REMOVE_COMPUTE_RESOURCES=false
CLI_TEST_ITEMS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-compute-resources)
      REMOVE_COMPUTE_RESOURCES=true
      shift
      ;;
    --help)
      show_help
      ;;
    --*)
      show_help
      ;;
    *)
      CLI_TEST_ITEMS+="$1 "
      shift
      ;;
  esac
done

if [[ -n "$CLI_TEST_ITEMS" ]]; then
  TEST_ITEMS="${CLI_TEST_ITEMS% }"  # Remove trailing space
else
  TEST_ITEMS="${TEST_ITEMS:-}"      # Use env var or empty string
fi

if [ -z "${TEST_ITEMS}" ]
then
  show_help
fi

if [ -z "${USE_TRUSTED_ARTIFACTS}" ]
then
  echo "Defaulting to PVC based workspaces..."
  # empty is needed since trusted-artifacts needs a non-empty storage
  # parameter in order to reach the skipping logic
  export TRUSTED_ARTIFACT_OCI_STORAGE="empty"
else

  echo "Using Trusted Artifacts for workspaces..."
  export TRUSTED_ARTIFACT_OCI_STORAGE=registry-service.kind-registry/trusted-artifacts
  export TRUSTED_ARTIFACT_OCI_DOCKER_CONFIG_JSON_PATH=${DOCKER_CONFIG_JSON}

  echo "Using docker config stored in ${DOCKER_CONFIG_JSON}"
  kubectl create secret generic docker-config \
    --from-file=.dockerconfigjson="${TRUSTED_ARTIFACT_OCI_DOCKER_CONFIG_JSON_PATH}" \
    --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | kubectl apply -f -
  kubectl patch serviceaccount default -p \
    '{"imagePullSecrets": [{"name": "docker-config"}], "secrets": [{"name": "docker-config"}]}'

fi

# Check that all directories exist. If not, fail
for ITEM in $TEST_ITEMS
do
  if [[ "$ITEM" == *tests/test-*.yaml && -f "$ITEM" ]]; then
    true
  elif [[ -d "$ITEM" ]]; then
    true
  else
    echo "Error: Invalid file or directory: $ITEM"
    exit 1
  fi
done

# install step actions
echo "Installing StepActions"
SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
STEPACTION_ROOT=${SCRIPT_DIR}/../../stepactions
stepActionFiles=$(find $STEPACTION_ROOT -maxdepth 2 -name "*.yaml")

for stepAction in ${stepActionFiles};
do
  name=$(yq ".metadata.name" "${stepAction}")
  echo "  Installing StepAction $name"
  kubectl apply -f $stepAction
done

# Clean up leftover resources from previous test runs to prevent cluster exhaustion
echo "Cleaning up old test resources..."
kubectl delete pipelineruns -l tekton.dev/pipeline --field-selector=status.conditions[0].status!=Unknown || true
kubectl get taskruns -o json | jq -r '.items[] | select(.status.completionTime != null) | select((now - (.status.completionTime | fromdateiso8601)) > 3600) | .metadata.name' | xargs -r kubectl delete taskrun --ignore-not-found=true || true

for ITEM in $TEST_ITEMS
do
  echo Task item: $ITEM
  TASK_NAME=$(echo $ITEM | cut -d '/' -f 3)
  TASK_DIR=$(echo $ITEM | cut -d '/' -f -3)
  echo "  Task name: $TASK_NAME"

  TASK_PATH=${TASK_DIR}/${TASK_NAME}.yaml
  if [ ! -f $TASK_PATH ]
  then
    echo Error: Task file does not exist: $TASK_PATH
    exit 1
  fi

  TESTS_DIR=${TASK_DIR}/tests
  if [ ! -d $TESTS_DIR ]
  then
    echo Error: tests dir does not exist: $TESTS_DIR
    exit 1
  fi

  if [[ "$ITEM" == *tests/test-*.yaml ]]; then
    TEST_PATHS=($ITEM)
  else
    TEST_PATHS=($TESTS_DIR/test*.yaml)
  fi
  if [ ${#TEST_PATHS[@]} -eq 0 ]
  then
    echo "  Warning: No tests. Skipping..."
    continue
  fi

  # Use a copy of the task file to prevent modifying to original task file
  TASK_COPY=$(mktemp)
  cp "$TASK_PATH" "$TASK_COPY"

  if [ -f ${TESTS_DIR}/pre-apply-task-hook.sh ]
  then
    echo Found pre-apply-task-hook.sh file in dir: $TESTS_DIR. Executing...
    ${TESTS_DIR}/pre-apply-task-hook.sh "$TASK_COPY"
  fi

  # Update stepaction resolvers
  # - we want to remove the git resolver params so we can use the StepAction on cluster
  echo "Updating StepAction resolvers"
  for stepAction in ${stepActionFiles};
  do
    name=$(yq ".metadata.name" "${stepAction}")
    echo "  Update resolver for $name"
    yq -i "(.spec.steps[] | select(.name == \"$name\") | .ref) = {\"name\": \"$name\"}" $TASK_COPY
  done

  if [[ "$REMOVE_COMPUTE_RESOURCES" == "true" ]]; then
    echo "Removing compute resources from task $TASK_NAME"
    yq -i 'del(.spec.steps[].computeResources)' "$TASK_COPY"
  fi

  echo "  Installing task"
  kubectl apply -f "$TASK_COPY"

  if [ -z "${USE_TRUSTED_ARTIFACTS}" ]; then
    workSpaceParams="volumeClaimTemplateFile=$WORKSPACE_TEMPLATE"
    dataDir=/workspace/data
  else
    workSpaceParams="emptyDir="
    # to avoid tar extraction errors, we need to specify a subdirectory
    # inside the volume.
    dataDir=/var/workdir/release
  fi

  rm -f "$TASK_COPY"

  for TEST_PATH in ${TEST_PATHS[@]}
  do
    echo "  Installing test pipeline: $TEST_PATH"
    kubectl apply -f $TEST_PATH
    TEST_NAME=$(yq '.metadata.name' $TEST_PATH)

    # If a test is creating a trusted artifact, provide the necessary parameters to it.
    # This way, we can support testing TA-based tasks which do not produce any artifacts
    # directly. If a task requires a TA strategy, the test will also need to utilize the
    # strategy to run successfully.
    # If a test doesn't use the parameters, it is considered a PVC-only test and should
    # continue to work.
    ociStorageParamCheck=$(yq '(.spec.params[] | select(.name == "ociStorage"))' "$TEST_PATH")
    ociStorageParam=""
    if [ ! -z "${ociStorageParamCheck}" ]; then
      ociStorageParam="-p ociStorage=${TRUSTED_ARTIFACT_OCI_STORAGE}"
    fi
    dataDirParamCheck=$(yq '(.spec.params[] | select(.name == "dataDir"))' "$TEST_PATH")
    dataDirParam=""
    if [ ! -z "${dataDirParamCheck}" ]; then
      dataDirParam="-p dataDir=${dataDir}"
    fi

    # Sometimes the pipeline is not available immediately
    while ! kubectl get pipeline $TEST_NAME > /dev/null 2>&1
    do
      echo "  Pipeline $TEST_NAME not ready. Waiting 5s..."
      sleep 5
    done

    PIPELINERUNJSON=$(tkn p start --use-param-defaults $TEST_NAME ${ociStorageParam} ${dataDirParam} -w "name=tests-workspace,${workSpaceParams}" -o json)
    PIPELINERUN=$(jq -r '.metadata.name' <<< "${PIPELINERUNJSON}")

    echo "  Started pipelinerun $PIPELINERUN"
    sleep 1  # allow a second for the pr object to appear (including a status condition)
    while [ "$(kubectl get pr $PIPELINERUN -o=jsonpath='{.status.conditions[0].status}')" == "Unknown" ]
    do
      echo "  PipelineRun $PIPELINERUN in progress (status Unknown). Waiting for update..."
      sleep 5
    done
    tkn pr logs $PIPELINERUN

    PR_STATUS=$(kubectl get pr $PIPELINERUN -o=jsonpath='{.status.conditions[0].status}')

    ASSERT_TASK_FAILURE=$(yq '.metadata.annotations.test/assert-task-failure' < $TEST_PATH)
    if [ "$ASSERT_TASK_FAILURE" != "null" ]
    then
      if [ "$PR_STATUS" == "True" ]
      then
        echo "  Pipeline $TEST_NAME succeeded but was expected to fail"
        exit 1
      else
        echo "  Pipeline $TEST_NAME failed (expected). Checking that it failed in task ${ASSERT_TASK_FAILURE}..."

        # Check that the pipelinerun failed on the tested task and not somewhere else
        TASKRUN=$(kubectl get pr $PIPELINERUN -o json|jq -r "(.status.childReferences // [])[] | select(.pipelineTaskName == \"${ASSERT_TASK_FAILURE}\") | .name")
        if [ -z "$TASKRUN" ]
        then
          echo "    Unable to find task $ASSERT_TASK_FAILURE in childReferences of pipelinerun $PIPELINERUN. Pipelinerun failed earlier?"
          kubectl get pr $PIPELINERUN -o json
          exit 1
        else
          echo "    Found taskrun $TASKRUN"
        fi
        if [ $(kubectl get tr $TASKRUN -o=jsonpath='{.status.conditions[0].status}') != "False" ]
        then
          echo "    Taskrun did not fail - pipelinerun failed later on?"
          kubectl get tr $TASKRUN -o json
          exit 1
        else
          echo "    Taskrun failed as expected"
        fi

      fi
    else
      if [ "$PR_STATUS" == "True" ]
      then
        echo "  Pipelinerun $TEST_NAME succeeded"
      else
        echo "  Pipelinerun $TEST_NAME failed"
        exit 1
      fi
    fi

    # Cleanup test resources to prevent cluster exhaustion when running many tests
    echo "  Cleaning up test resources..."
    kubectl delete pipelinerun $PIPELINERUN --ignore-not-found=true
    kubectl delete pipeline $TEST_NAME --ignore-not-found=true

    # Clean up old completed PipelineRuns (keep only last 5 to avoid filling the cluster)
    OLD_PRS=$(kubectl get pipelineruns -o json | jq -r '.items[] | select(.status.conditions[0].status != "Unknown") | .metadata.name' | head -n -5)
    if [ ! -z "$OLD_PRS" ]; then
      echo "$OLD_PRS" | xargs -r kubectl delete pipelinerun --ignore-not-found=true
    fi
    echo
  done

  # Cleanup task after all its tests complete
  echo "Cleaning up task $TASK_NAME"
  kubectl delete task $TASK_NAME --ignore-not-found=true

done
