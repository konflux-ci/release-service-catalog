#!/usr/bin/env bash
set -eux

function update_component_sbom() {
  echo Mock update_component_sbom called with: "$*"
  echo "$*" >> "$(params.dataDir)/mock_update.txt"

  if [[ "$1" != "--snapshot-path" ]] ||
     [[ "$2" != "$(params.dataDir)/$(params.subdirectory)/snapshot_spec.json" ]] ||
     [[ "$3" != "--release-id" ]] ||
     [[ "$4" != "$(params.releaseId)" ]] ||
     [[ "$5" != "--output-path" ]] ||
     [[ "$6" != "$(params.dataDir)/$(params.subdirectory)/sboms" ]]; then
    echo "Error: Unexpected call"
    exit 1
  fi
}
