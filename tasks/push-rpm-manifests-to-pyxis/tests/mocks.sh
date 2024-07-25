#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(workspaces.data.path)/mock_cosign.txt

  if [[ "$*" != "download sbom --output-file myImageID"[1-5]*".json imageurl"[1-5] && \
     "$*" != "download sbom --output-file myImageID"[1-5]*".json --platform linux/"*" multiarch-"[1-5] ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  touch /workdir/sboms/${4}
}

function upload_rpm_manifest() {
  echo Mock upload_rpm_manifest called with: $*
  echo $* >> $(workspaces.data.path)/mock_upload_rpm_manifest.txt

  if [[ "$*" != "--retry --image-id "*" --sbom-path "*".json --verbose" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  if [[ "$3" == myImageID1Failing ]]
  then
    echo "Simulating a failing RPM Manifest push..."
    return 1
  fi

  if [[ "$3" == myImageID?Parallel ]]
  then
    LOCK_FILE=$(workspaces.data.path)/${3}.lock
    touch $LOCK_FILE
    sleep 2
    LOCK_FILE_COUNT=$(ls $(workspaces.data.path)/*.lock | wc -l)
    echo $LOCK_FILE_COUNT > $(workspaces.data.path)/${3}.count
    sleep 2
    rm $LOCK_FILE
  fi
}
