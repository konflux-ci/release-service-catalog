#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function sleep() {
  echo "mocked sleep with arg:" "$*"
}
