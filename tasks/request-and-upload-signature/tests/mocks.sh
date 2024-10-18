#!/usr/bin/env bash
set -eux

count_file="/tmp/request-signature-failure-count.txt"
if [[ ! -f "$count_file" ]]; then
    echo "0" > "$count_file"
fi


function ssh() {
    # Read the current ssh_call_count from the file
    ssh_call_count=$(cat "$count_file")
    ssh_call_count=$((ssh_call_count + 1))
    echo "$ssh_call_count" > "$count_file"

    echo "$ssh_call_count" > "$(workspaces.data.path)/ssh_calls.txt"
}

function request-signature() {
  echo Mock request-signature called with: $*
  echo $* >> $(workspaces.data.path)/mock_request-signature.txt

  requester=$(echo $* | grep -oP 'requester \K\w+')
  file=$(echo $* | grep -oP 'output (.+)$' | cut -f2 -d' ')
  touch "${file}"

  if [ "${requester}" == "iamgoingtofail" ]; then
    echo "forcing a failure to get a retry"
    # Read the current ssh_call_count from the file
    call_count=$(cat "$count_file")
    call_count=$((call_count + 1))
    echo "$call_count" > "$count_file"
    echo "$call_count" > "$(workspaces.data.path)/request-signature-failure-count.txt"
    return 1
  fi

  echo "{}" > "${file}"
}

function upload-signature() {
  echo Mock upload-signature called with: $*
  echo $* >> $(workspaces.data.path)/mock_upload-signature.txt
  cat signing_response.json
}
