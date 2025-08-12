#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function kinit() {
  echo "Mock kinit called with: $*"

  # Write to both locations to support both modes
  if [ -d /workspace/kmods ]; then
    echo "$*" >> /workspace/kmods/mock_kinit.txt
  fi
  if [ -d "$(params.dataDir)" ]; then
    echo "$*" >> "$(params.dataDir)"/mock_kinit.txt
  fi

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

  # Write to both locations to support both modes
  if [ -d /workspace/kmods ]; then
    echo "$*" >> /workspace/kmods/mock_ssh.txt
  fi
  if [ -d "$(params.dataDir)" ]; then
    echo "$*" >> "$(params.dataDir)"/mock_ssh.txt
  fi

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

  # Write to both locations to support both modes
  if [ -d /workspace/kmods ]; then
    echo "$*" >> /workspace/kmods/mock_scp.txt
  fi
  if [ -d "$(params.dataDir)" ]; then
    echo "$*" >> "$(params.dataDir)"/mock_scp.txt
  fi

  case "$*" in
    "-o UserKnownHostsFile=/root/.ssh/known_hosts -o GSSAPIAuthentication=yes -o GSSAPIDelegateCredentials=yes"*)
      ;;
    *)
      echo "Error: Incorrect scp parameters"
      exit 1
      ;;
  esac
}

# The retry script won't see the kinit function unless we export it
export -f kinit
