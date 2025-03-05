#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function oras(){
  echo Mock oras called with: "$*"
  echo "$*" >> "$(params.dataDir)/mock_oras.txt"

  if [[ "$*" == "pull --registry-config"* ]]
  then
    echo Mock oras called with: "$*"
    echo $4
    IFS='/' arrIN=(${4}); unset IFS;
    IFS='@' zip=(${arrIN[2]}); unset IFS;
    registry="$4"
    hash=${registry##*@sha256:}
    short_hash=${hash:0:6}
    chmod 777 /workdir/mrrc/"$short_hash"
    touch /workdir/mrrc/"$short_hash"/"${zip[0]}"
  else
    echo Mock oras called with: "$*"
    echo Error: Unexpected call
    exit 1
  fi
}

function charon(){
  echo Mock charon called with: "$*"
  echo "$*" >> "$(params.dataDir)/mock_charon.txt"

  if [ ! -f "$HOME/.charon/charon.yaml" ]
  then
    echo Error: Missing charon config file
    exit 1
  fi

  if [[ "$*" != "sign -r "*" -p "*" -k "*" "*"" ]] && [[ "$*" != "upload -p "*" -v "*" -t "*" "*"" ]]
  then
    echo Mock charon called with: "$*"
    echo Error: Unexpected call
    exit 1
  fi

  # generate signing file to pass test
  if [[ "$*" == "sign -r "*" -p "*" -k "*" "*"" ]]
  then
    echo Mock charon sign called with: "$*"
    registry="$8"
    hash=${registry##*@sha256:}
    short_hash=${hash:0:6}
    touch /workdir/mrrc/"$short_hash"/signing.json
  fi

  # will use testcert as a symbol for ca mounted test
  if [[ "$*" == "sign -r "*" -p "*" -k \"testcert\" "*"" ]]
  then
    if [[ $(cat /etc/ssl/certs/ca-custom-bundle.crt) != "mycert" ]]
    then
      echo Custom certificate not mounted
      return 1
    fi
  fi
}

function select-oci-auth() {
  echo "$*" >> "$(params.dataDir)/mock_select-oci-auth.txt"
}

