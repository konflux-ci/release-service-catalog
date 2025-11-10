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

function pubtools-sign-msg-container-sign() {
  >&2 echo "Mock pubtools-sign-msg-container-sign called with: $*"
  echo "$*" >> "$(workspaces.data.path)/mock_pubtools-sign.txt"
  cat "$(workspaces.data.path)/mocked_signing_response"
}

function pubtools-pyxis-upload-signatures() {
  >&2 echo "Mock pubtools-pyxis-upload-signatures called with: $*"
  echo "$*" >> "$(workspaces.data.path)/mock_pubtools-pyxis-upload-signatures.txt"
}

function openssl() {
  >&2 echo "Mock openssl called with: $*"
  echo "$*" >> "$(workspaces.data.path)/mock_openssl.txt"
  if [[ "$*" =~ "x509 -noout -subject" ]]; then
    echo "UID=test-mock"
  fi
}

export CUSTOM_TASK_ID="1234"

function find_signatures() {
  echo $* >> $(workspaces.data.path)/mock_find_signatures.txt

  reference=$(echo $* | grep -oP 'repository \K\w+')
  file=$(echo $* | grep -oP 'output_file (.+)$' | cut -f2 -d' ')
  touch "${file}"

  cat "$(workspaces.data.path)/mocked_signatures/${reference}" > "${file}"
}
