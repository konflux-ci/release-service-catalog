#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  /home/utils/internal-request $@

  sleep 1
  NAME=$(kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
      --sort-by=.metadata.creationTimestamp | tail -1)
  if [ -z $NAME ]; then
      echo Error: Unable to get IR name
      echo Internal requests:
      kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
          --sort-by=.metadata.creationTimestamp
      exit 1
  fi

  if [[ "$*" == *'snapshot_json={"application":"disk-images","components":[{"name":"failing-disk-image"}'* ]]; then
      set_ir_status $NAME Failure
  elif [[ "$*" == *"exodusGwEnv="@(live|pre)* ]]; then
      set_ir_status $NAME Succeeded
  else
      echo Unexpected call to internal-request
      exit 1
  fi
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    echo Setting status of $NAME to reason $REASON  >&2
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "reason": "${REASON}",
        "lastTransitionTime": "2023-12-06T15:22:45Z",
        "message": "my message",
        "status": "True",
        "type": "merge"
      }
    ]
  }
}
EOF
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    echo '{"result":"Success"}'
  else
    /usr/bin/kubectl $*
  fi
}
