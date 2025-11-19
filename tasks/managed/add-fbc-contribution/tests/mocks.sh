#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  # Use WORKDIR env var instead of $(params.dataDir) for subshell compatibility
  local WORKDIR="${WORKDIR:-/var/workdir/release}"
  printf '%s\n' "$*" >> "$WORKDIR/mock_internal-request.txt"

  # Extract unique identifier from the task context that we can use for labeling
  PIPELINE_UID=""
  for arg in "$@"; do
    if [[ "$arg" == *"pipelinerun-uid="* ]]; then
      PIPELINE_UID=$(echo "$arg" | sed 's/.*pipelinerun-uid=//')
      break
    fi
  done

  # set to async and capture output
  # Use a unique temp file for each internal-request call to avoid race conditions in parallel execution
  local ir_output_file
  ir_output_file="$WORKDIR/ir-output-${PIPELINE_UID:-default}-$$.tmp"
  /home/utils/internal-request "$@" -s false | tee "$ir_output_file"

  sleep 1
  
  # Extract the IR name from the captured output specific to this pipeline
  IR_NAME=$(awk -F"'" '/created/ { print $2 }' "$ir_output_file")
  
  if [ -z "$IR_NAME" ]; then
      # Fallback: try to find IR with matching pipeline UID label
      if [ -n "$PIPELINE_UID" ]; then
        IR_NAME=$(kubectl get internalrequest -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" --no-headers -o custom-columns=":metadata.name" --sort-by=.metadata.creationTimestamp | tail -1)
      fi
      
      # Final fallback to the original method
      if [ -z "$IR_NAME" ]; then
        IR_NAME=$(kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
            --sort-by=.metadata.creationTimestamp | tail -1)
      fi
  fi
  
  if [ -z "$IR_NAME" ]; then
      echo "Error: Unable to get IR name for pipeline UID: ${PIPELINE_UID:-none}"
      echo "Internal requests:"
      kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
          --sort-by=.metadata.creationTimestamp
      exit 1
  fi

  # Check if fbcFragments contains the fail.io pattern
  # The parameter comes in format: -p fbcFragments=["fail.io/image0@sha256:0000"]
  # Any image with "fail.io" in the registry/path will trigger a failure
  if [[ "$*" =~ fbcFragments=.*fail\.io ]]; then
      set_ir_status $IR_NAME 1
  else
      set_ir_status $IR_NAME 0
  fi
}

function set_ir_status() {
    NAME=$1
    EXITCODE=$2
    local WORKDIR="${WORKDIR:-/var/workdir/release}"
    PATCH_FILE="$WORKDIR/${NAME}-patch.json"

    # Determine condition status based on exit code - matches internal-services behavior
    if [ "${EXITCODE}" -eq 0 ]; then
        CONDITION_STATUS="True"
        CONDITION_REASON="Succeeded"
        CONDITION_MESSAGE=""
    else
        CONDITION_STATUS="False"
        CONDITION_REASON="Failed"
        CONDITION_MESSAGE="Internal request failed with exit code ${EXITCODE}"
    fi

    # Match real internal-services behavior: results are extracted from PipelineRun and stored as map[string]string
    # For failures (exitCode != 0), do not provide results as they would be empty in real scenarios
    if [ "${EXITCODE}" -eq 0 ]; then
        cat > $PATCH_FILE << EOF
{
  "status": {
    "results": {
      "jsonBuildInfo": "$(echo '{"updated":"2024-03-06T16:39:11.314092Z", "index_image": "redhat.com/rh-stage/iib:01", "index_image_resolved": "redhat.com/rh-stage/iib@sha256:abcdefghijk"}' | gzip -c | base64 -w0)",
      "indexImageDigests": "quay.io/a quay.io/b",
      "iibLog": "Dummy IIB Log",
      "exitCode": "${EXITCODE}"
    },
    "conditions": [
      {
        "type": "Succeeded",
        "status": "${CONDITION_STATUS}",
        "reason": "${CONDITION_REASON}",
        "message": "${CONDITION_MESSAGE}",
        "lastTransitionTime": "$(/usr/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
      }
    ]
  }
}
EOF
    else
        # For failures, only provide conditions without results (matches real behavior)
        cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "type": "Succeeded",
        "status": "${CONDITION_STATUS}",
        "reason": "${CONDITION_REASON}",
        "message": "${CONDITION_MESSAGE}",
        "lastTransitionTime": "$(/usr/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
      }
    ]
  }
}
EOF
    fi
    # Add retry logic for the patch operation to handle timing issues
    for attempt in 1 2 3 4 5; do
        if kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE; then
            echo "Successfully patched InternalRequest $NAME on attempt $attempt"
            break
        else
            echo "Patch attempt $attempt failed for InternalRequest $NAME, retrying in 2 seconds..."
            if [ $attempt -eq 5 ]; then
                echo "ERROR: Failed to patch InternalRequest $NAME after 5 attempts"
                echo "Available InternalRequests:"
                kubectl get internalrequest --no-headers -o custom-columns=":metadata.name"
                exit 1
            fi
            sleep 2
        fi
    done
}

function date() {
  local WORKDIR="${WORKDIR:-/var/workdir/release}"
  echo $* >> "$WORKDIR/mock_date.txt"

  case "$*" in
      "+%Y-%m-%dT%H:%M:%SZ")
          echo "2023-10-10T15:00:00Z" |tee "$WORKDIR/mock_date_iso_format.txt"
          ;;
      "+%s")
          echo "1696946200" | tee "$WORKDIR/mock_date_epoch.txt"
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

# Set WORKDIR for subshell compatibility (replaces $(params.dataDir) which doesn't expand in subshells)
export WORKDIR="$(params.dataDir)"

# Export functions so they're available to the task scripts
export -f internal-request
export -f set_ir_status
export -f date
