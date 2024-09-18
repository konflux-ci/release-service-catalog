#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function oras(){
  echo Mock oras called with: $*
  echo $* >> $(workspaces.data.path)/mock_oras.txt

  if [[ "$*" == "pull --registry-config"* ]]
  then
    echo Mock oras called with: $*
    echo $4
    IFS='/' arrIN=(${4}); unset IFS;
    IFS='@' zip=(${arrIN[2]}); unset IFS;
    touch /workdir/mrrc/$zip
  else
    echo Mock oras called with: $*
    echo Error: Unexpected call
    exit 1
  fi
}

function charon(){
  echo Mock charon called with: $*
  echo $* >> $(workspaces.data.path)/mock_charon.txt

  if [ ! test -f "$HOME/.charon/charon.yaml" ]
  then
    echo Error: Missing charon config file
    exit 1
  fi

  if [[ "$*" != "upload -p "*" -v "*" -t "*" "*"" ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}

function select-oci-auth() {
  echo $* >> $(workspaces.data.path)/mock_select-oci-auth.txt
}

