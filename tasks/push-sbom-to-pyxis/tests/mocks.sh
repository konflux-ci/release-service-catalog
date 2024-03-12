#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(workspaces.data.path)/mock_cosign.txt

  if [[ "$*" != "download sbom --output-file myImageID"*".json source"?"@mydigest"? ]]
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
    LOCK_FILE=$(workspaces.data.path)/${3}.lock
    touch $LOCK_FILE
    sleep 1
    LOCK_FILE_COUNT=$(ls $(workspaces.data.path)/*.lock | wc -l)
    echo $LOCK_FILE_COUNT > $(workspaces.data.path)/${3}.count
    sleep 1
    rm $LOCK_FILE
  fi
}
