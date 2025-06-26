#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request "$@" -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function internal-pipelinerun() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-pipelinerun "$@" -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function find_signatures() {
  echo $* >> $(workspaces.data.path)/mock_find_signatures.txt

  reference=$(echo $* | grep -oP 'repository \K\w+')
  file=$(echo $* | grep -oP 'output_file (.+)$' | cut -f2 -d' ')
  touch "${file}"

  if [ "${repository}" == "already/signed" ]; then
    echo "registry.redhat.io/already/signed:some-prefix" >> "${file}"
    echo "registry.access.redhat.com/already/signed:some-prefix" >> "${file}"
  fi
}
