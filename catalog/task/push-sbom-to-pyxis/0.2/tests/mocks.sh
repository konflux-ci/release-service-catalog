#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*

  if [[ "$*" != "download sbom --output-file myImageID"[12]".json imageurl"[12] ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  touch /workdir/sboms/${4}
}

function upload_sbom() {
  echo Mock upload_sbom called with: $*

  if [[ "$*" != "--retry --sbom-path "*".json" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}
