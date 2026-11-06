#!/usr/bin/env bash
set -eux

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
  elif [[ $# -eq 0 ]]; then
    /usr/bin/mktemp
  else
    echo Error: Unexpected call
    exit 1
  fi
}

function curl() {
  echo "Mock curl called with: $*" >&2

  if [[ "$*" == *"-sL --fail-with-body -K "* && \
        "$*" == *"https://some-url.com/api/v4/projects/group%2Fproject/repository/files/path%2Fto%2Fadvisory.yaml/raw?ref=main -o"* ]]
  then
    echo "mock" >&2
  else
    echo Error: Unexpected call
    exit 1
  fi
}
