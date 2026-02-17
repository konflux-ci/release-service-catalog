#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  # Use WORKDIR env var instead of $(params.dataDir) for subshell compatibility
  local WORKDIR="${WORKDIR:-/var/workdir/release}"
  printf '%s\n' "$*" >> "$WORKDIR/mock_internal-request.txt"

  # Extract unique identifiers from the task context that we can use for labeling
  PIPELINE_UID=""
  IR_SEQUENCE=""
  for arg in "$@"; do
    if [[ "$arg" == *"pipelinerun-uid="* ]]; then
      PIPELINE_UID="${arg##*pipelinerun-uid=}"
    elif [[ "$arg" == *"ir-sequence="* ]]; then
      IR_SEQUENCE=$(echo "$arg" | sed 's/.*ir-sequence=//' | sed 's/"//g')
    fi
  done

  # set to async and capture output
  # Use a unique temp file for each internal-request call to avoid race conditions in parallel execution
  local ir_output_file
  ir_output_file="$WORKDIR/ir-output-${PIPELINE_UID:-default}-$$.tmp"

  # Count existing IRs before creating new one to track which one we created
  local ir_count_before=0
  if [ -n "$PIPELINE_UID" ]; then
    ir_count_before=$(kubectl get internalrequest \
      -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" \
      --no-headers 2>/dev/null | wc -l)
  fi
  
  # Redirect internal-request output to stderr to avoid polluting stdout
  # The task only needs to parse "InternalRequest 'NAME' created" from stdout
  /home/utils/internal-request "$@" -s false 2>&1 | tee "$ir_output_file" >&2

  # Extract the IR name from the captured output - the real command outputs JSON/status
  # We'll get the name from k8s after creation instead of parsing output
  IR_NAME=""
  
  # Extract expected labels early so we can use them for IR discovery
  local batch_number=""
  local ocp_version=""
  for arg in "$@"; do
    if [[ "$arg" == "batch-number="* ]]; then
      batch_number="${arg#batch-number=}"
    elif [[ "$arg" == "ocp-version="* ]]; then
      ocp_version="${arg#ocp-version=}"
    fi
  done
  
  if [ -z "$IR_NAME" ]; then
      # Poll for the new IR to appear (wait up to 10 seconds)
      # CRITICAL: In parallel execution, multiple workers share the same PIPELINE_UID
      # We MUST filter by ocp-version and batch-number to find the correct IR for THIS worker
      if [ -n "$PIPELINE_UID" ]; then
        echo "Waiting for InternalRequest (pipeline-uid=${PIPELINE_UID}, batch=${batch_number}, ocp=${ocp_version}, sequence=${IR_SEQUENCE})..." >&2
        
        # Try using IR_SEQUENCE first if available (most specific identifier)
        if [ -n "$IR_SEQUENCE" ]; then
          echo "Attempting IR discovery by sequence: ${IR_SEQUENCE}..." >&2
          for attempt in {1..30}; do
            IR_NAME=$(kubectl get internalrequest \
              -l "ir-sequence=${IR_SEQUENCE}" \
              -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" \
              --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
            if [ -n "$IR_NAME" ]; then
              echo "Found IR by sequence: $IR_NAME (attempt $attempt)" >&2
              break
            fi
            sleep 0.3
          done
        fi
        
        # Fallback to OCP version + batch number if IR_SEQUENCE didn't work
        if [ -z "$IR_NAME" ]; then
          for attempt in {1..30}; do
            sleep 0.3
            local ir_count_after
            
            # Build the query with all available label filters to identify THIS worker's IR
            local label_filters="-l internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}"
            if [ -n "$batch_number" ]; then
              label_filters="$label_filters -l batch-number=${batch_number}"
            fi
            if [ -n "$ocp_version" ]; then
              label_filters="$label_filters -l ocp-version=${ocp_version}"
            fi
          
            ir_count_after=$(kubectl get internalrequest \
              $label_filters \
              --no-headers 2>/dev/null | wc -l)
            
            if [ "$ir_count_after" -gt "$ir_count_before" ]; then
              # New IR appeared with our specific labels, get the most recent one
              IR_NAME=$(kubectl get internalrequest \
                $label_filters \
                --no-headers -o custom-columns=":metadata.name" \
                --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -1)
              if [ -n "$IR_NAME" ]; then
                echo "Found InternalRequest: $IR_NAME (attempt $attempt)" >&2
                break
              fi
            fi
          done
        fi
      fi
      
      # Final fallback: get most recent IR that matches our OCP version
      # DO NOT fall back to getting ANY IR - that causes workers to reuse IRs from other OCP versions
      if [ -z "$IR_NAME" ] && [ -n "$ocp_version" ] && [ -n "$PIPELINE_UID" ]; then
        echo "WARNING: Polling timed out, trying fallback query with ocp-version filter" >&2
        IR_NAME=$(kubectl get internalrequest \
          -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" \
          -l "ocp-version=${ocp_version}" \
          --no-headers -o custom-columns=":metadata.name" \
          --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -1)
      elif [ -z "$IR_NAME" ]; then
        # Last resort fallback if we don't have labels
        echo "WARNING: Falling back to getting most recent IR (no labels available)" >&2
        IR_NAME=$(kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
            --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -1)
      fi
  fi
  
  if [ -z "$IR_NAME" ]; then
      echo "Error: Unable to get IR name for pipeline UID: ${PIPELINE_UID:-none}" >&2
      echo "Internal requests:" >&2
      kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
          --sort-by=.metadata.creationTimestamp >&2
      exit 1
  fi

  # Verify that labels were actually applied to the InternalRequest
  echo "Verifying labels on InternalRequest: $IR_NAME" >&2
  local expected_labels=()
  
  # Extract expected labels from the command arguments
  # (batch_number and ocp_version were already extracted above for IR discovery)
  for arg in "$@"; do
    if [[ "$arg" == "-l" ]]; then
      continue
    elif [[ "$arg" == "batch-number="* ]]; then
      expected_labels+=("batch-number=${batch_number}")
    elif [[ "$arg" == "ocp-version="* ]]; then
      expected_labels+=("ocp-version=${ocp_version}")
    elif [[ "$arg" == *"pipelinerun-uid="* ]]; then
      local uid="${arg#*pipelinerun-uid=}"
      expected_labels+=("pipelinerun-uid=${uid}")
    fi
  done
  
  # Wait for labels to be applied with retry logic
  # Under memory pressure, K8s API can be slower - use exponential backoff
  # Use moderate retry count to balance robustness with performance
  local max_label_wait_attempts=15
  local verification_failed=0
  
  for wait_attempt in $(seq 1 $max_label_wait_attempts); do
    verification_failed=0
    # Brief sleep before verification, increasing slightly over time
    if [[ $wait_attempt -le 5 ]]; then
      sleep 0.1
    elif [[ $wait_attempt -le 10 ]]; then
      sleep 0.2
    else
      sleep 0.3
    fi
    
    # Verify each expected label
    for label_pair in "${expected_labels[@]}"; do
      local label_key="${label_pair%%=*}"
      local label_value="${label_pair#*=}"
      
      # Handle the long pipelinerun-uid label key
      if [[ "$label_key" == "pipelinerun-uid" ]]; then
        label_key="internal-services.appstudio.openshift.io/pipelinerun-uid"
      fi
      
      local actual_value
      actual_value=$(kubectl get internalrequest "$IR_NAME" \
        -o jsonpath="{.metadata.labels['${label_key}']}" 2>/dev/null || echo "")
      
      if [[ "$actual_value" != "$label_value" ]]; then
        verification_failed=1
        if [[ $wait_attempt -ge 10 ]]; then
          echo "DEBUG: Label verification attempt $wait_attempt: ${label_key} expected='${label_value}' actual='${actual_value}'" >&2
        fi
        break  # Exit inner loop if any label doesn't match
      fi
    done
    
    # If all labels verified successfully, break out of retry loop
    if [[ $verification_failed -eq 0 ]]; then
      echo "✓ Labels verified for $IR_NAME (attempt $wait_attempt)" >&2
      break
    fi
    
    # If this was the last attempt, show warning but continue
    # In memory-constrained environments, this is acceptable
    if [[ $wait_attempt -eq $max_label_wait_attempts ]]; then
      echo "WARNING: Label verification incomplete for $IR_NAME after $max_label_wait_attempts attempts" >&2
      echo "This can occur under memory pressure - continuing with test" >&2
      
      # Show what we expected vs what we got for debugging
      echo "Expected labels:" >&2
      for label_pair in "${expected_labels[@]}"; do
        echo "  - $label_pair" >&2
      done
      
      echo "Actual labels on $IR_NAME:" >&2
      { kubectl get internalrequest "$IR_NAME" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "(unable to retrieve)"; echo ""; } >&2
      
      # Don't fail - label propagation delays are acceptable in test environments
      # The task's own retry logic will catch any real issues
      break
    fi
  done

  # Output the expected format for awk parsing (before set_ir_status which outputs other messages)
  echo "InternalRequest '$IR_NAME' created"
  
  # Check if fbcFragments contains the fail.io pattern
  # The parameter comes in format: -p fbcFragments=["fail.io/image0@sha256:0000"]
  # Any image with "fail.io" in the registry/path will trigger a failure
  # Set status synchronously to ensure it's done before returning
  if [[ "$*" =~ fbcFragments=.*fail\.io ]]; then
      set_ir_status "$IR_NAME" 1
  else
      set_ir_status "$IR_NAME" 0
  fi
  
  # CRITICAL: Ensure kubectl label selectors can properly filter by the labels we just applied
  # This is MANDATORY - we must not return until kubectl can consistently query the IR
  # with ALL label selectors (pipeline-uid, batch-number, ocp-version) and get exactly 1 result
  echo "Verifying kubectl label selector consistency with ALL filters..." >&2
  
  local final_verify_success=false
  local max_final_attempts=30  # Increased from 20 to handle severe API lag
  
  for verify_attempt in $(seq 1 $max_final_attempts); do
    # Query using ALL label selectors that the task will use
    local found_count=0
    if [ -n "$batch_number" ] && [ -n "$ocp_version" ] && [ -n "$PIPELINE_UID" ]; then
      found_count=$(kubectl get internalrequests \
        -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" \
        -l "batch-number=${batch_number}" \
        -l "ocp-version=${ocp_version}" \
        --no-headers 2>/dev/null | { grep -c "^${IR_NAME}\s" || true; })
    elif [ -n "$batch_number" ] && [ -n "$PIPELINE_UID" ]; then
      # Fallback if no ocp-version
      found_count=$(kubectl get internalrequests \
        -l "internal-services.appstudio.openshift.io/pipelinerun-uid=${PIPELINE_UID}" \
        -l "batch-number=${batch_number}" \
        --no-headers 2>/dev/null | { grep -c "^${IR_NAME}\s" || true; })
    else
      # If we don't have the necessary labels, just verify by name
      if kubectl get internalrequest "$IR_NAME" &>/dev/null; then
        final_verify_success=true
        break
      fi
    fi
    
    if [ "$found_count" -eq "1" ]; then
      final_verify_success=true
      if [ $verify_attempt -gt 1 ]; then
        echo "✓ Final kubectl verification passed on attempt $verify_attempt" >&2
      fi
      break
    else
      if [ $verify_attempt -ge 10 ]; then
        echo "DEBUG: Final verification attempt $verify_attempt: Found $found_count IRs (expected 1) for" \
             "pipeline-uid=${PIPELINE_UID}, batch=${batch_number}, ocp=${ocp_version}" >&2
      fi
      
      # Progressive backoff: longer waits as attempts increase
      if [ $verify_attempt -le 10 ]; then
        sleep 0.5
      elif [ $verify_attempt -le 20 ]; then
        sleep 1
      else
        sleep 2
      fi
    fi
  done
  
  if [ "$final_verify_success" = "false" ]; then
    echo "WARNING: Final kubectl verification incomplete for IR $IR_NAME after $max_final_attempts attempts" >&2
    echo "Expected kubectl to consistently return exactly 1 IR with these labels:" >&2
    echo "  - pipeline-uid: ${PIPELINE_UID}" >&2
    echo "  - batch-number: ${batch_number}" >&2
    echo "  - ocp-version: ${ocp_version}" >&2
    echo "" >&2
    echo "This may indicate Kubernetes API cache inconsistency under load (parallel workers)." >&2
    echo "The task's own query logic will retry if needed." >&2
    echo "Current labels on $IR_NAME:" >&2
    { kubectl get internalrequest "$IR_NAME" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "(unable to retrieve)"; echo ""; } >&2
    # Don't exit 1 here - let the task handle it with its own retry logic
  fi
}

function set_ir_status() {
    NAME=$1
    EXITCODE=$2
    local WORKDIR="${WORKDIR:-/var/workdir/release}"
    PATCH_FILE="$WORKDIR/${NAME}-patch.json"
    
    # Wait for the IR to actually exist before trying to patch it
    echo "Waiting for InternalRequest $NAME to be created..." >&2
    for wait_attempt in {1..30}; do
      if kubectl get internalrequest "$NAME" &>/dev/null; then
        echo "InternalRequest $NAME found (attempt $wait_attempt)" >&2
        break
      fi
      if [ "$wait_attempt" -eq 30 ]; then
        echo "ERROR: InternalRequest $NAME not found after 15 seconds" >&2
        kubectl get internalrequest --no-headers >&2
        return 1
      fi
      sleep 0.5
    done

    # DEFENSIVE CHECK: Verify we're not patching an IR that already has status (RACE CONDITION FIX)
    # This prevents duplicate status patches when multiple workers mistakenly try to patch the same IR
    existing_status=$(kubectl get internalrequest "$NAME" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "")
    if [ -n "$existing_status" ] && [ "$existing_status" != "Unknown" ]; then
      echo "WARNING: InternalRequest $NAME already has status ($existing_status), skipping duplicate patch" >&2
      echo "This indicates a race condition where another worker tried to patch this IR" >&2
      echo "IR: $NAME, existing status: $existing_status" >&2
      return 0  # Don't fail - just skip the duplicate patch
    fi

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
        cat > "$PATCH_FILE" << EOF
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
        cat > "$PATCH_FILE" << EOF
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
    
    # Patch with retry logic for transient API errors, but maintain visibility
    local retry_count=0
    local max_retries=5
    local patch_succeeded=0
    
    while [ $retry_count -lt $max_retries ]; do
        if kubectl patch internalrequest "$NAME" --type=merge --subresource status \
            --patch-file "$PATCH_FILE" >&2 2>&1; then
            patch_succeeded=1
            break
        fi
        
        # Check if IR exists - if not, this is a test bug, log and give up
        if ! kubectl get internalrequest "$NAME" &>/dev/null; then
            echo "ERROR: Mock tried to patch non-existent InternalRequest $NAME" >&2
            return 0  # Don't fail tests, but logged the error
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            sleep 0.2  # Brief delay for API contention
        fi
    done
    
    if [ $patch_succeeded -eq 0 ]; then
        echo "WARNING: Failed to patch InternalRequest $NAME after $max_retries attempts" >&2
        echo "This may cause test timeouts or flakiness" >&2
    fi
    
    return 0  # Don't fail tests for mock issues
}

function date() {
  local WORKDIR="${WORKDIR:-/var/workdir/release}"
  echo "$*" >> "$WORKDIR/mock_date.txt"

  case "$*" in
      "+%Y-%m-%dT%H:%M:%SZ")
          echo "2023-10-10T15:00:00Z" |tee "$WORKDIR/mock_date_iso_format.txt"
          ;;
      "+%s")
          echo "1696946200" | tee "$WORKDIR/mock_date_epoch.txt"
          ;;
      "-u +%Hh%Mm%Ss -d @"*)
          /usr/bin/date "$@"
          ;;
      "+%s -d "*)
          # Handle date parsing for timestamp conversion (used in results processing)
          /usr/bin/date "$@"
          ;;
      *)
          # Fallback to real date for any other patterns
          /usr/bin/date "$@"
          ;;
  esac
}

# Set WORKDIR for subshell compatibility (replaces $(params.dataDir) which doesn't expand in subshells)
WORKDIR="$(params.dataDir)"
export WORKDIR

# Export functions so they're available to the task scripts
export -f internal-request
export -f set_ir_status
export -f date
