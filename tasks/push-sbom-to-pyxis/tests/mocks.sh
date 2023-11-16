#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(workspaces.data.path)/mock_cosign.txt

  if [[ "$*" != "download sbom --output-file myImageID"*".json imageurl"[1-5] ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  touch /workdir/sboms/${4}
}

function upload_sbom() {
  echo Mock upload_sbom called with: $*
  echo $* >> $(workspaces.data.path)/mock_upload_sbom.txt

  if [[ "$*" != "--retry --sbom-path "*".json" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  if [[ "$3" == myImageID1Failing.json ]]
  then
    echo "Simulating a failing sbom push..."
    return 1
  fi

  if [[ "$3" == myImageID?Parallel.json ]]
  then
    echo "Adding a small sleep"
    sleep 0.3
  fi
}
