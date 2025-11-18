#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> "$(params.dataDir)/mock_internal-request.txt"

  # set to async
  /home/utils/internal-request $@ -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function kubectl() {
  if [[ $* != *"get internalrequest"* ]]
  then
    echo "Unexpected call to kubectl"
    exit 1
  fi

  echo -n "dummy-payload" | base64
}

function gpg() {
  # Handle --list-packets for signature validation (idempotent behavior)
  if [[ "$*" == *"--list-packets"* ]]; then
    # Extract the file path from the arguments (last argument)
    local file_path="${@: -1}"
    
    # Check if the file contains "corrupted" text (invalid signature)
    if [ -f "$file_path" ] && grep -q "corrupted" "$file_path" 2>/dev/null; then
      # Invalid/corrupted signature
      return 1
    else
      # Valid binary signature
      return 0
    fi
  elif [[ "$*" == *"--dearmor"* ]]; then
    # For signature creation, just pass through the input
    echo -n "dummy-payload"
  else
    echo -n "dummy-payload"
  fi
}
