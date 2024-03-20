#!/usr/bin/env bash
set -eux

function opm() {
  echo $* >> $(workspaces.data.path)/mock_opm.txt
  if [[ "$*" == "render "* ]]
  then
    echo '{"schema": "olm.package","name": "test-package-1"}'
  else
    echo Mock opm called with: $*
    if [[ "$*" != "render "* ]]
    then
      echo Error: Unexpected call
      exit 1
    fi
  fi
}
