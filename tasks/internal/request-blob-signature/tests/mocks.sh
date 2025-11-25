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

function pubtools-sign-msg-blob-sign() {
  >&2 echo "Mock pubtools-sign-msg-blob-sign called with: $*"
  echo "$*" >> "$(workspaces.data.path)/mock_pubtools-sign.txt"
  cat "$(workspaces.data.path)/mocked_signing_response"
}

function openssl() {
  >&2 echo "Mock openssl called with: $*"
  echo "$*" >> "$(workspaces.data.path)/mock_openssl.txt"
  if [[ "$*" =~ "x509 -noout -subject" ]]; then
    echo "UID=test-mock"
  fi
}

function mktemp() {
  if [[ "${1:-}" == "-d" ]]; then
    dir=$(/usr/bin/mktemp -d)
    echo -e "---\n" > "${dir}/advisory.yaml"
    echo "${dir}"
  else
    echo "temp_file"
  fi
}

function python3() {
  >&2 echo "Mock python3 called with: $*"
}

export CUSTOM_TASK_ID="1234"
