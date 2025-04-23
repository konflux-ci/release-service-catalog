#!/usr/bin/env bash

set -euxo pipefail

# mocks to be injected into task step scripts
function git() {
  echo "Mock git called with: $*"

  if [[ "$*" == *"clone"* ]]; then
    gitRepo=$(awk '{print $NF}' <<< $*)
    mkdir -p "$gitRepo"/internal-services/manager
    echo "image: quay.io/konflux-ci/internal-services:old" | tee \
      "$gitRepo"/internal-services/manager/one.yaml \
      "$gitRepo"/internal-services/manager/two.yaml \
      "$gitRepo"/internal-services/manager/three.yaml
  else
    # Mock the other git functions to pass
    : # no-op - do nothing
  fi
}

function gh() {
  echo "Mock gh called with: $*"
}
