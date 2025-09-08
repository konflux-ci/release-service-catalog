#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function kinit() {
  echo "Mock kinit called with: $*"
  
  echo "$*" >> "$(params.dataDir)/mock_kinit.txt"

  case "$*" in
    "-kt /etc/sec-keytab/keytab-build-and-sign.keytab"*)
      ;;
    *)
      echo "Error: Incorrect kinit call"
      exit 1
      ;;
  esac
}

function ssh() {
  echo "Mock ssh called with: $*"
  
  echo "$*" >> "$(params.dataDir)/mock_ssh.txt"

  case "$*" in
    "-o UserKnownHostsFile=/root/.ssh/known_hosts -o GSSAPIAuthentication=yes -o GSSAPIDelegateCredentials=yes"*)
      ;;
    *)
      echo "Error: Incorrect ssh parameters"
      exit 1
      ;;
  esac
}

function scp() {
  echo "Mock scp called with: $*"
  
  echo "$*" >> "$(params.dataDir)/mock_scp.txt"

  case "$*" in
    "-o UserKnownHostsFile=/root/.ssh/known_hosts -o GSSAPIAuthentication=yes -o GSSAPIDelegateCredentials=yes"*)
      ;;
    *)
      echo "Error: Incorrect scp parameters"
      exit 1
      ;;
  esac
}
