#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function select-oci-auth() {
  echo '{"auths": {"quay.io": {"auth": "abcdefg"}}}'
}

function oras() {
  echo Mock oras called with: $*
  echo $* >> $(workspaces.data.path)/mock_oras.txt

  if [[ "$*" == "pull --registry-config "*" quay.io/ai/amd64-build@sha256:1234567" ]] ; then
    echo test | gzip > disk-amd64.qcow2.gz
    echo test | gzip > disk-amd64.raw.gz
  elif [[ "$*" == "pull --registry-config "*" quay.io/ai/intel-build@sha256:1234567" ]] ; then
    echo test | gzip > disk-intel.qcow2.gz
    echo test | gzip > disk-intel.raw.gz
  elif [[ "$*" == "pull --registry-config "*" quay.io/ai/nvidia-build@sha256:1234567" ]] ; then
    echo test | gzip > disk-nvidia.qcow2.gz
    echo test | gzip > disk-nvidia.raw.gz
  elif [[ "$*" == "pull --registry-config "*" quay.io/ai/amd64-parallel@sha256:1234567" ]] ; then
    date +%s%3N >> $(workspaces.data.path)/parallel_dates.txt
    sleep 2
    echo test | gzip > disk-amd64.qcow2.gz
    echo test | gzip > disk-amd64.raw.gz
  elif [[ "$*" == "pull --registry-config "*" quay.io/ai/intel-parallel@sha256:1234567" ]] ; then
    date +%s%3N >> $(workspaces.data.path)/parallel_dates.txt
    sleep 2
    echo test | gzip > disk-intel.qcow2.gz
    echo test | gzip > disk-intel.raw.gz
  else
    echo Error: Unexpected call
    exit 1
  fi

}
