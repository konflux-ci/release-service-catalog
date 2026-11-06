#!/usr/bin/env bash
set -eu

# mocks to be injected into task step scripts
function select-oci-auth() {
    echo >&2 "Mock select-oci-auth called with: $*"
}

function oras() {
    echo "Mock oras called with: $*"
}

function mktemp() {
  echo >&2 "Mock mktemp called with: $*"
  if [[ "${1:-}" == "-d" ]]; then
    dir=$(/usr/bin/mktemp -d)
    echo -e "---\n" > "${dir}/advisory.yaml"
    echo "${dir}"
  else
    echo Error: Unexpected call
    exit 1
  fi
}

function curl() {
  echo "Mock curl called with: $*" >&2

  if [[ "$*" == *"-sL --fail-with-body https://some-url.com/advisory.yaml -o"* ]]
  then
    echo "mock" >&2
  else
    echo Error: Unexpected call
    exit 1
  fi
}
