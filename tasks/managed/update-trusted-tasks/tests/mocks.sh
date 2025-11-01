#!/bin/bash
set -eux

# mocks to be injected into task step scripts
function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_skopeo.txt"

  # Verify CA certificate is accessible if mounted
  if [[ -d /mnt/trusted-ca ]]; then
    if [[ ! -f /mnt/trusted-ca/ca-bundle.crt ]]; then
      echo "Error: CA certificate not found at /mnt/trusted-ca/ca-bundle.crt"
      return 1
    fi
    echo "CA certificate is accessible at /mnt/trusted-ca/ca-bundle.crt" >&2
  fi

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

