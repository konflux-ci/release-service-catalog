#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    echo '{"result":"Success","advisory_url":"https://access.redhat.com/errata/RHBA-2025:1111"}'
  else
    /usr/bin/kubectl $*
  fi
}

function oras() {
  echo "Mock oras called with: $*"
  if [[ "$*" =~ pull.* ]]; then
    # Create checksum_map.json from mock data file if it exists
    # Check in shared workdir (for cross-pod tests) or /tmp (for same-pod tests)
    MOCK_DATA=""
    if [ -f /var/workdir/release/mock_checksum_map.json ]; then
      MOCK_DATA="/var/workdir/release/mock_checksum_map.json"
    elif [ -f /tmp/mock_checksum_map.json ]; then
      MOCK_DATA="/tmp/mock_checksum_map.json"
    fi
    
    if [ -n "$MOCK_DATA" ]; then
      # Create tar.gz archive containing checksum_map.json (matching production format)
      cp "$MOCK_DATA" checksum_map.json
      tar -czf checksum_map checksum_map.json
      rm checksum_map.json
      echo "Mock oras: created checksum_map archive from $MOCK_DATA"
    else
      echo "Mock oras: no mock data found at /var/workdir/release/mock_checksum_map.json or /tmp/mock_checksum_map.json"
      exit 1
    fi
  fi
}
