#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request $@ -s false

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

  if [[ "$*" == *"fbcFragment=fail.io"* ]]; then
      set_ir_status $NAME 1
  else
      set_ir_status $NAME 0
  fi
}

function set_ir_status() {
    NAME=$1
    EXITCODE=$2
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    cat > $PATCH_FILE << EOF
{
  "status": {
    "results": {
      "genericResult": "{\"fbc_opt_in\":\"true\",\"publish_index_image\":\"false\",\"sign_index_image\":\"false\"}",
      "iibLog": "Dummy IIB Log",
      "exitCode": "${EXITCODE}"
    }
  }
}
EOF
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}

function date() {
  echo $* >> $(workspaces.data.path)/mock_date.txt

  case "$*" in
      "+%Y-%m-%dT%H:%M:%SZ")
          echo "2023-10-10T15:00:00Z" |tee $(workspaces.data.path)/mock_date_iso_format.txt
          ;;
      "+%s")
          echo "1696946200" | tee $(workspaces.data.path)/mock_date_epoch.txt
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}
