#!/usr/bin/env bash
set -eux

# Mock git
function git() {
  echo "Mock git called with: $*"

  if [[ "$1" == "clone" ]]; then
    mkdir -p "$6"
  elif [[ "$1" == "sparse-checkout" ]]; then
    : # no-op
  elif [[ "$1" == "checkout" ]]; then
    mkdir -p data/advisories/test-origin
  else
    echo "Error: Unexpected git command: $*" >&2
    exit 1
  fi
}

# Mock find
function find() {
  echo "Mock find called with: $*" >&2

  if echo "$*" | grep -q "not-existing-origin"; then
    # Simulate missing advisory directory
    return 0
  fi

  if echo "$*" | grep -q "${ADVISORY_BASE_DIR}"; then
    echo "1712012345.0 ${ADVISORY_BASE_DIR}/2025/1602"
    echo "1712012344.0 ${ADVISORY_BASE_DIR}/2025/1601"
    echo "1708012343.0 ${ADVISORY_BASE_DIR}/2024/1452"
    echo "1704012342.0 ${ADVISORY_BASE_DIR}/2024/1442"
  else
    echo "Error: Unexpected find command: $*" >&2
    exit 1
  fi
}

# Mock yq
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
  elif [[ "$2" == ".spec.content.images // []" ]]; then
    case "$advisory_num" in
      1601)
        # Include entries that match our get-image-architectures mock digests
        echo '[
          {"containerImage":"registry.redhat.io/test@sha256:releasedarch123","tags":["v1.0"],"repository":"registry.redhat.io/test"},
          {"containerImage":"registry.redhat.io/test@sha256:amd64digest123","tags":["v1.0"],"repository":"registry.redhat.io/test"},
          {"containerImage":"registry.redhat.io/test@sha256:arm64digest456","tags":["v1.0"],"repository":"registry.redhat.io/test"}
        ]'
        ;;
      1602)
        echo '[{"containerImage":"quay.io/test/other-image:1.0.0","tags":["stable"],"repository":"quay.io/test"}]'
        ;;
      1452)
        echo '[{"containerImage":"quay.io/test/legacy-image:2.0.0","tags":["old"],"repository":"quay.io/legacy"}]'
        ;;
      1442)
        echo '[{"containerImage":"quay.io/test/conflict-image:3.1.4","tags":["conflict", "v3"],"repository":"quay.io/test-conflict"}]'
        ;;
      *)
        echo "Error: Unexpected advisory number $advisory_num" >&2
        exit 1
        ;;
    esac
  else
    echo "Error: Unexpected yq query: $2" >&2
    exit 1
  fi
}
