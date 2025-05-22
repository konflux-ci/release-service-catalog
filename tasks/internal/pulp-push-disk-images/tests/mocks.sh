#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function select-oci-auth() {
    echo Mock select-oci-auth called with: $*
}

function oras() {
    echo Mock oras called with: $*

    if [[ "$*" != "pull --registry-config"* ]]; then
        echo Error: Unexpected call to oras
        exit 1
    fi

    if [[ "$*" == *"nonexistent-disk-image"* ]]; then
        echo Simulating failing oras pull call
        exit 1
    fi

    touch disk.qcow2
    touch disk.raw.gz
    touch fail_gzip.raw.gz
}

# We aren't going to pull real files that can be unzipped, so just remove the .gz suffix on them
function gzip() {
    if [ $2 == "fail_gzip.raw.gz" ] ; then
        echo gzip failed
        exit 1
    fi
    mv $2 ${2::-3}
}

function pulp_push_wrapper() {
    echo Mock pulp_push_wrapper called with: $*

    if [[ "$*" != *"--pulp-url https://pulp.com"* ]]; then
        printf "Mocked failure of pulp_push_wrapper" > /nonexistent/location
    fi
}

function publish_to_cgw_wrapper() {
  echo "Mock publish_to_cgw_wrapper called with: $*"

  /home/publish-to-cgw-wrapper/publish_to_cgw_wrapper "$@" --dry_run

  if [[ "$?" -ne 0 ]]; then
    echo "Unexpected failure in publish_to_cgw_wrapper dry-run"
    exit 1
  fi
}
