#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  printf '%s\n' "$*" >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request "$@" -s false

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

  if [[ "$*" == *"fbcFragments="*"fail.io"* ]]; then
      set_ir_status $NAME 1
  else
      set_ir_status $NAME 0
  fi
}

function set_ir_status() {
    NAME=$1
    EXITCODE=$2
    PATCH_FILE=$(params.dataDir)/${NAME}-patch.json
    cat > $PATCH_FILE << EOF
{
  "status": {
    "results": {
      "jsonBuildInfo": "{\"updated\":\"2024-03-06T16:39:11.314092Z\", \"index_image\": \"redhat.com/rh-stage/iib:01\", \"index_image_resolved\": \"redhat.com/rh-stage/iib@sha256:abcdefghijk\"}",
      "indexImageDigests": "quay.io/a quay.io/b",
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
  echo $* >> $(params.dataDir)/mock_date.txt

  case "$*" in
      "+%Y-%m-%dT%H:%M:%SZ")
          echo "2023-10-10T15:00:00Z" |tee $(params.dataDir)/mock_date_iso_format.txt
          ;;
      "+%s")
          echo "1696946200" | tee $(params.dataDir)/mock_date_epoch.txt
          ;;
      "-u +%Hh%Mm%Ss -d @"*)
          /usr/bin/date $*
          ;;
      "-u +%Hh%Mm%Ss -d @"*)
          usr/bin/date $*
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}
