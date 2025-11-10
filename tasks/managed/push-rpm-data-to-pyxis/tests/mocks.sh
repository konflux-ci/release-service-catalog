#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(params.dataDir)/mock_cosign.txt

  if [[ "$*" == "download sbom --output-file myImageID"[1-5]*".json imageurl"[1-5] ]]; then
    : # do nothing
  elif [[ "$*" == "download sbom --output-file myImageID"[1-5]*".json --platform linux/"*" multiarch-"[1-5] ]]; then
    : # do nothing
  elif [[ "$*" == "download sbom --output-file myImageID"[1-5]*".json retryimage" ]]; then
    if [[ "$(wc -l < "$(params.dataDir)/mock_cosign.txt")" -lt 3 ]]; then
      echo "Error: simulated cosign download sbom failure" 1>&2
      return 1
    else
      echo "Success: simulated cosign download sbom" 1>&2
    fi
  else
    echo Error: Unexpected call
    exit 1
  fi

  SBOM_JSON='{"spdxVersion": "SPDX-2.3"}'

  echo "$SBOM_JSON" > "/var/workdir/downloaded-sboms/${4}"
  # Also save a copy in the dataDir for test verification
  mkdir -p "$(params.dataDir)/downloaded-sboms"
  echo "$SBOM_JSON" > "$(params.dataDir)/downloaded-sboms/${4}"
}

function upload_rpm_data() {
  echo Mock upload_rpm_data called with: $*
  echo $* >> "$(params.dataDir)/mock_upload_rpm_data.txt"

  if [[ "$*" != "--retry --image-id "*" --sbom-path "*".json --verbose" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  if [[ "$3" == myImageID1Failing ]]
  then
    echo "Simulating a failing RPM data push..."
    return 1
  fi

  if [[ "$3" == myImageID?Parallel ]]
  then
    LOCK_FILE=$(params.dataDir)/${3}.lock
    mkdir -p $(params.dataDir)
    touch $LOCK_FILE
    sleep 2
    LOCK_FILE_COUNT=$(ls $(params.dataDir)/*.lock | wc -l)
    echo $LOCK_FILE_COUNT > $(params.dataDir)/${3}.count
    sleep 2
    rm $LOCK_FILE
  fi

  return 0
}

function select-oci-auth() {
  echo $* >> $(params.dataDir)/mock_select-oci-auth.txt
}
