#!/bin/bash
set -eux

# mocks to be injected into task step scripts
function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_skopeo.txt"

  if [[ "$*" =~ list-tags\ docker://quay.io/exists ]]; then
      echo '{"Tags": ["v2.0.0-3", "latest", "v2.0.0-2"]}'
      return
  elif [[ "$*" =~ list-tags\ docker://quay.io ]]; then
      echo '{"Tags": ["v2.0.0-4", "v2.0.0-3", "v2.0.0-2"]}'
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

function curl() {
  echo Mock curl called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_curl.txt"

  # Mock successful API call to make repository public
  if [[ "$*" =~ "quay.io/api/v1/repository".*"changevisibility" ]]; then
      echo '{"success": true}'
      return 0
  fi
  
  # Pass through other curl calls
  command curl "$@"
}

