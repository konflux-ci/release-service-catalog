#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request $@ -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function kubectl() {
  if [[ "$*" == *"get internalrequest"*"-o json"* ]]
  then
    # Check if this is the failure test case by looking for a marker file in dataDir
    # The dataDir is mounted at /var/workdir/release by default
    if [ -f /var/workdir/release/.test-failure-marker ]; then
      echo '{
        "status": {
          "conditions": [
            {
              "type": "Succeeded",
              "status": "False",
              "reason": "Failed",
              "message": "Failed to publish index image: permission denied to registry"
            }
          ],
          "results": {
            "requestMessage": "Error: Failed to push image"
          }
        }
      }'
    else
      # Return successful status for normal tests
      echo '{
        "status": {
          "conditions": [
            {
              "type": "Succeeded",
              "status": "True",
              "reason": "Succeeded",
              "message": ""
            }
          ],
          "results": {
            "requestMessage": "Index Image Published successfully"
          }
        }
      }'
    fi
  elif [[ "$*" == *"get internalrequest"*"jsonpath"*"status.results"* ]]
  then
    if [ -f /var/workdir/release/.test-failure-marker ]; then
      echo '{"requestMessage":"Error: Failed to push image"}'
    else
      echo '{"requestMessage":"Index Image Published successfully"}'
    fi
  else
    /usr/bin/kubectl $*
  fi
}
