#!/bin/bash

# This script will run task tests for all task directories
# provided either via TASK_DIRS env var, or as arguments
# when running the script.
#
# Requirements:
# - Connection to a running k8s cluster (e.g. kind)
# - Tekton installed on the cluster
# - tkn installed
#
# Examples of usage:
# export TASK_DIRS="mydir/task/apply-mapping/0.3 some/other/dir/0.1"
# ./test_tekton_tasks.sh
#
# or
#
# ./test_tekton_tasks.sh mydir/task/apply-mapping/0.3 some/other/dir/0.1

# yield empty strings for unmatched patterns
shopt -s nullglob

WORKSPACE_TEMPLATE=${BASH_SOURCE%/*/*}/resources/workspace-template.yaml

if [ $# -gt 0 ]
then
  TASK_DIRS=$@
fi

if [ -z "${TASK_DIRS}" ]
then
  echo Error: No task directories.
  echo Usage:
  echo "$0 [DIR1] [DIR2] [...]"
  echo
  echo or
  echo
  echo "export TASK_DIRS=\"DIR1 DIR2 ...\""
  echo "$0"
  exit 1
fi

# Check that all directories exist. If not, fail
for DIR in $TASK_DIRS
do
  if [ ! -d "$DIR" ]
  then
    echo "Error: Directory does not exist: $DIR"
    exit 1
  fi
done

for DIR in $TASK_DIRS
do
  echo Task dir: $DIR
  TASK_NAME=${DIR%/*}
  TASK_NAME=${TASK_NAME##*/}
  echo "  Task name: $TASK_NAME"

  TASK_PATH=${DIR}/${TASK_NAME}.yaml
  if [ ! -f $TASK_PATH ]
  then
    echo Error: Task file does not exist: $TASK_PATH
    exit 1
  fi

  TESTS_DIR=${DIR}/tests
  if [ ! -d $TESTS_DIR ]
  then
    echo Error: tests dir does not exist: $TESTS_DIR
    exit 1
  fi

  TEST_PATHS=($TESTS_DIR/test*.yaml)
  if [ ${#TEST_PATHS[@]} -eq 0 ]
  then
    echo "  Warning: No tests. Skipping..."
    continue
  fi

  echo "  Installing task"
  kubectl apply -f $TASK_PATH

  for TEST_PATH in ${TEST_PATHS[@]}
  do
    echo "  Installing test pipeline: $TEST_PATH"
    kubectl apply -f $TEST_PATH
    TEST_NAME=${TEST_PATH##*/}
    TEST_NAME=${TEST_NAME%.*}
    PIPELINERUN=$(tkn p start $TEST_NAME -w name=tests-workspace,volumeClaimTemplateFile=$WORKSPACE_TEMPLATE -o json | jq -r '.metadata.name')
    echo "  Started pipelinerun $PIPELINERUN"
    tkn pr logs $PIPELINERUN -f
    while [ "$(kubectl get pr $PIPELINERUN -o=jsonpath='{.status.conditions[0].status}')" == "Unknown" ]
    do
      echo "  PipelineRun $PIPELINERUN status Unknown. Waiting for update..."
      sleep 5
    done

    if [ "$(kubectl get pr $PIPELINERUN -o=jsonpath='{.status.conditions[0].status}')" == "True" ]
    then
      echo "  Pipelinerun succeeded"
    else
      echo "  Pipelinerun failed"
      exit 1
    fi
  done

done
