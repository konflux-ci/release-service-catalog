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
    "-o UserKnownHostsFile=~/.ssh/known_hosts -o GSSAPIAuthentication=yes -o GSSAPIDelegateCredentials=yes"*)
      ;;
    *)
      echo "Error: Incorrect ssh parameters"
      exit 1
      ;;
  esac
}

function rm() {
  echo "Mock rm called with: $*"

  echo "$*" >> "$(params.dataDir)/mock_rm.txt"

  case "$*" in
    "-f "*"/*.ko")
      ;;
    "-f "*signed-kmods*)
      ;;
    *)
      echo "Error: Unexpected rm parameters: $*"
      exit 1
      ;;
  esac
}

function scp() {
  echo "Mock scp called with: $*"

  echo "$*" >> "$(params.dataDir)/mock_scp.txt"

  case "$*" in
    "-o UserKnownHostsFile=~/.ssh/known_hosts -o GSSAPIAuthentication=yes -o GSSAPIDelegateCredentials=yes"*)
      # Check if this is the download command (contains *.ko in remote path)
      if [[ "$*" == *"~/kmods/*.ko"* ]]; then
        # This is the download command - extract destination directory (last argument)
        local args=($*)
        local dest_path="${args[-1]}"
        echo "Mock scp: Creating signed files in destination: $dest_path"
        if [ -d "$dest_path" ]; then
          echo "SIGNED_MODULE1" > "$dest_path/mod1.ko"
          echo "SIGNED_MODULE2" > "$dest_path/mod2.ko"
          echo "Mock scp: Created signed files in $dest_path"
        else
          echo "Mock scp: Warning - destination directory $dest_path does not exist"
        fi
      fi
      # For upload command, we don't need to do anything special
      ;;
    *)
      echo "Error: Incorrect scp parameters"
      exit 1
      ;;
  esac
}
