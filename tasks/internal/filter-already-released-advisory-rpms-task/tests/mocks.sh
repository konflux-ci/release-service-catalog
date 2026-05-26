#!/usr/bin/env bash
set -eux

function select-oci-auth() {
  echo "/dev/null"
}

function oras() {
  echo "Mock oras called with: $*" >&2

  if [[ "$1" == "push" ]]; then
    return 0
  elif [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
    echo '{"digest": "sha256:mockdigest123"}'
    return 0
  else
    echo "Error: Unexpected oras command: $*" >&2
    exit 1
  fi
}

function git() {
  echo "Mock git called with: $*"

  if [[ "$1" == "clone" ]]; then
    mkdir -p "$6"
  elif [[ "$1" == "sparse-checkout" ]]; then
    :
  elif [[ "$1" == "checkout" ]]; then
    mkdir -p data/advisories/test-origin/2025/1601
    mkdir -p data/advisories/test-origin/2025/1602
    touch data/advisories/test-origin/2025/1601/advisory.yaml
    touch data/advisories/test-origin/2025/1602/advisory.yaml
  else
    echo "Error: Unexpected git command: $*" >&2
    exit 1
  fi
}

function find() {
  echo "Mock find called with: $*" >&2

  if echo "$*" | grep -q "no-advisories-origin"; then
    return 0
  fi

  if echo "$*" | grep -q "${ADVISORY_BASE_DIR}"; then
    echo "1712012345.0 ${ADVISORY_BASE_DIR}/2025/1602"
    echo "1712012344.0 ${ADVISORY_BASE_DIR}/2025/1601"
  else
    echo "Error: Unexpected find command: $*" >&2
    exit 1
  fi
}

function yq() {
  echo "Mock yq called with: $*" >&2

  if [[ "$1" == "-o=json" ]]; then
    local advisory_path="$3"
    local advisory_num
    advisory_num=$(echo "$advisory_path" | awk -F'/' '{print $(NF-1)}')

    case "$advisory_num" in
      1601)
        echo '["pkg:rpm/redhat/released-rpm@1.0-1.fc44?arch=x86_64", "pkg:rpm/redhat/all-released-a@1.0-1.fc44?arch=x86_64", "pkg:rpm/redhat/all-released-b@2.0-1.fc44?arch=x86_64"]'
        ;;
      *)
        echo '[]'
        ;;
    esac
  elif [[ "$1" == "-r" ]]; then
    local advisory_path="$3"
    local advisory_num
    advisory_num=$(echo "$advisory_path" | awk -F'/' '{print $(NF-1)}')

    if [[ "$2" == ".spec.type" ]]; then
      echo "RHBA"
    elif [[ "$2" == ".metadata.name" ]]; then
      local advisory_year
      advisory_year=$(echo "$advisory_path" | awk -F'/' '{print $(NF-2)}')
      echo "${advisory_year}:${advisory_num}"
    else
      echo "Error: Unexpected yq -r query: $2" >&2
      exit 1
    fi
  else
    echo "Error: Unexpected yq command: $*" >&2
    exit 1
  fi
}

