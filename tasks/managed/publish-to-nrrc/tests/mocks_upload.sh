#!/usr/bin/env bash
set -euxo pipefail

# Mock for bash script steps (upload-npm-archive)
# Python entrypoint mocks are in tests/mocks.yaml and tests/mocks/

function charon(){
  echo Mock charon called with: "$*" >&2
  echo "$*" >> "$(params.dataDir)/mock_charon.txt"

  if [ ! -f "${HOME}/.charon/charon.yaml" ]
  then
    echo Error: Missing charon config file >&2
    exit 1
  fi

  case "$1" in
    "upload")
      echo Mock charon upload called with: "$*" >&2
      # Record CA certificate status for mount-certs test validation
      CA_FILE="/etc/ssl/certs/ca-custom-bundle.crt"
      if [[ -f "${CA_FILE}" ]]; then
        CA_CONTENT=$(cat "${CA_FILE}")
        echo "ca_file_exists=true" >> "$(params.dataDir)/mock_ca_status.txt"
        echo "ca_content=${CA_CONTENT}" >> "$(params.dataDir)/mock_ca_status.txt"
      else
        echo "ca_file_exists=false" >> "$(params.dataDir)/mock_ca_status.txt"
      fi
      return 0
      ;;
    *)
      echo Error: Unexpected charon command: "$1" >&2
      exit 1
      ;;
  esac
}

