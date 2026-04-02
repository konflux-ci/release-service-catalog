#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts for rh-sign-rpm testing

function internal-request() {
  TIMEOUT=30
  END_TIME=$(date -ud "$TIMEOUT seconds" +%s)

  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

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

  if [[ "$*" == *"expected-ir-failure"* ]]; then
      set_ir_status $NAME Failure 5
  elif [[ "$*" == *"expected-timeout-failure"* ]]; then
      echo "skipping setting IR status since we want a timeout..."
  else
      set_ir_status $NAME Succeeded 5
  fi
  wait -n
  EXIT_CODE=$?
  echo "internal-request completed with exit code: $EXIT_CODE" >&2
  return $EXIT_CODE
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
    PATCH_FILE=$(params.dataDir)/${NAME}-patch.json
    status="True"
    if [ "${REASON}" == "Failure" ]; then
      status="False"
      # For failure, don't include signed_rpms_oci_artifact
      cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "reason": "${REASON}",
        "lastTransitionTime": "2023-12-06T15:22:45Z",
        "message": "my message",
        "status": "${status}",
        "type": "merge"
      }
    ],
    "results": {}
  }
}
EOF
    else
      cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "reason": "${REASON}",
        "lastTransitionTime": "2023-12-06T15:22:45Z",
        "message": "my message",
        "status": "${status}",
        "type": "merge"
      }
    ],
    "results": {
      "signed_rpms_oci_artifact": "oci://registry.example.com/signed-rpms/${NAME}@sha256:abc123"
    }
  }
}
EOF
    fi
    echo "Calling kubectl patch for $NAME..."
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}
