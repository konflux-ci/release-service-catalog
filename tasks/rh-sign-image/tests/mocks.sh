#!/usr/bin/env bash
set -eux

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

  if [[ "$*" == *"requester=testuser-failure"* ]]; then
      set_ir_status $NAME Failure 3 &
  else
      set_ir_status $NAME Succeeded 10 &
  fi
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
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
