#!/bin/bash
set -eux

# mocks to be injected into task step scripts
function date() {
  # Return a fixed timestamp for testing
  if [[ "$*" == "+%s" ]]; then
      echo "1234567890"
      return
  fi

  # Fall back to real date for other uses
  command date "$@"
}

function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_skopeo.txt"

  if [[ "$*" =~ inspect.*docker://quay.io/exists.*:latest ]]; then
      # Exists repo has :latest tag - return success
      return 0
  elif [[ "$*" =~ inspect.*docker://quay.io/.*:latest ]]; then
      # Other repos don't have :latest tag - return failure
      return 1
  elif [[ "$*" =~ ^copy ]]; then
      # Mock skopeo copy - just record that it was called
      return
  fi

  echo Error: Unexpected call
  exit 1
}

function ec() {
  echo Mock ec called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_ec.txt"

  if [[ "$*" =~ "track bundle".*fail-image.* ]]; then
      exit 1

  elif [[ "$*" =~ "track bundle".* ]]; then
      return
  fi

  echo Error: Unexpected call
  exit 1
}

