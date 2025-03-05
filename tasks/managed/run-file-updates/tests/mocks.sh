#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function internal-request() {
  TIMEOUT=30
  END_TIME=$(date -ud "$TIMEOUT seconds" +%s)

  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  # since we put the IR in the background, we need to be able to locate it so we can
  # get the name to patch it. We do this by tacking on another random label that we can use
  # to select with later.
  rando=$(openssl rand -hex 12)
  /home/utils/internal-request "$@" -l "internal-services.appstudio.openshift.io/test-id=$rando" &

  sleep 2
  NAME=
  while [[ -z ${NAME} ]]; do
    if [ "$(date +%s)" -gt "$END_TIME" ]; then
        echo "ERROR: Timeout while waiting to locate InternalRequest"
        echo "Internal requests:"
        kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
            --sort-by=.metadata.creationTimestamp
        exit 124
    fi

    NAME=$(kubectl get internalrequest -l "internal-services.appstudio.openshift.io/test-id=$rando" \
        --no-headers -o custom-columns=":metadata.name" \
        --sort-by=.metadata.creationTimestamp | tail -1)
    if [ -z $NAME ]; then
        echo "Warning: Unable to get IR name"
        sleep 2
    fi
  done
  echo "IR Name: $NAME"
  if [[ "$*" == *"ref=fail2"* ]]; then
      set_ir_status $NAME Failure 2
  elif [[ "$*" == *"ref=fail"* ]]; then
      set_ir_status $NAME Failure 5
  else
      set_ir_status $NAME Succeeded 5
  fi
  wait -n
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    status="Succeeded"
    mockPipelineRunName="$(openssl rand -hex 12)"
    mockTaskRunName="${mockPipelineRunName}-tr"
    if [ "${REASON}" == "Failure" ]; then
      status="Failed"
      cat > $PATCH_FILE << EOF
{
  "status": {
    "results": {
      "internalRequestPipelineRunName": "${mockPipelineRunName}",
      "internalRequestTaskRunName": "${mockTaskRunName}",
      "buildState": "$status",
      "jsonBuildInfo": "{\"error\":\"unknown error\",\"str\":\"unknown error\"}\n"
    }
  }
}
EOF
    else
      cat > $PATCH_FILE << EOF
{
  "status": {
    "results": {
      "internalRequestPipelineRunName": "${mockPipelineRunName}",
      "internalRequestTaskRunName": "${mockTaskRunName}",
      "buildState": "$status",
      "jsonBuildInfo": "{\"merge_request\":\"https://g/r/-/merge_requests/18\"}\n"
    }
  }
}
EOF

    fi
    echo "Calling kubectl patch for $NAME..."
    cat $PATCH_FILE
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}
