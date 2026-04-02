#!/usr/bin/env bash
set -eux

function git() {
  echo "Mock git called with: $*"

  if [[ "$1" == "clone" ]]; then
    mkdir -p "$6"
  elif [[ "$1" == "sparse-checkout" ]]; then
    :
  elif [[ "$1" == "checkout" ]]; then
    # Create advisory directory structure with advisory.yaml files
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

  if [[ -z "$3" ]]; then
    echo "Error: Empty file path in yq command" >&2
    exit 1
  fi

  advisory_path="$3"
  advisory_num=$(echo "$advisory_path" | awk -F'/' '{print $(NF-1)}')

  if [[ "$2" == ".spec.type" ]]; then
    echo "RHBA"
  elif [[ "$2" == ".metadata.name" ]]; then
    advisory_year=$(echo "$advisory_path" | awk -F'/' '{print $(NF-2)}')
    echo "${advisory_year}:${advisory_num}"
  elif [[ "$2" == *".spec.content.artifacts"* ]]; then
    case "$advisory_num" in
      1601)
        # These purls match RPMs that should be "in advisory"
        echo '["pkg:rpm/redhat/released-rpm@1.0-1.fc44?arch=x86_64", "pkg:rpm/redhat/all-released-a@1.0-1.fc44?arch=x86_64", "pkg:rpm/redhat/all-released-b@2.0-1.fc44?arch=x86_64"]'
        ;;
      1602)
        echo '[]'
        ;;
      *)
        echo '[]'
        ;;
    esac
  else
    echo "Error: Unexpected yq query: $2" >&2
    exit 1
  fi
}

