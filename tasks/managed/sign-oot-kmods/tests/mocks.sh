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
      # Handle directory creation commands with TaskRun UID
      if [[ "$*" == *"mkdir -p ~/"*"/kmods"* ]]; then
        echo "Mock ssh: Creating unique TaskRun directory structure"
        return 0
      fi
      # Handle cleanup commands with TaskRun UID
      if [[ "$*" == *"rm -rf ~/"*"/kmods"* ]] || [[ "$*" == *"rm -rf ~/"*[a-f0-9\-]* ]]; then
        echo "Mock ssh: Cleaning up unique TaskRun directory"
        return 0
      fi
      # Handle ls commands for verification
      if [[ "$*" == *"ls -la ~/"* ]]; then
        echo "Mock ssh: Listing directory contents"
        return 0
      fi
      # Handle ls commands for getting file lists (used for downloading)
      if [[ "$*" == *"cd ~/"*"/kmods"* && "$*" == *"ls -1 *.ko"* ]]; then
        echo "Mock ssh: Listing .ko files for download"
        # Return the list of .ko files that should be available after signing
        if [[ "$*" == *"/amd64/"* ]]; then
          echo "amd64-mod1.ko"
          echo "amd64-mod2.ko"
        elif [[ "$*" == *"/arm64/"* ]]; then
          echo "arm64-mod1.ko"
          echo "arm64-mod2.ko"
        else
          echo "mod1.ko"
          echo "mod2.ko"
        fi
        return 0
      fi
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
      # Actually remove the files for the mock to work correctly
      /bin/rm "$@"
      ;;
    "-f "*signed-kmods*)
      /bin/rm "$@"
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
      local args=($*)

      # Determine if this is an upload or download operation
      # Upload: local files followed by remote destination (last arg contains @host:)
      # Download: remote source (contains @host:) followed by local destination
      local is_download=false
      local remote_source=""
      local local_dest=""
      local last_arg="${args[-1]}"

      # Check if the last argument is a remote destination (contains @host:)
      if [[ "$last_arg" == *"@"*":"* ]]; then
        # This is an upload operation (last arg is remote destination)
        echo "Mock scp: Upload operation to $last_arg"
        # For upload commands, we don't need to create files locally
      else
        # Look for remote source in the arguments (not the last one)
        for arg in "${args[@]:0:${#args[@]}-1}"; do
          if [[ "$arg" == *"@"*":"* ]]; then
            is_download=true
            remote_source="$arg"
            local_dest="$last_arg"
            break
          fi
        done

        if [[ "$is_download" == true ]]; then
          # This is a download operation
          echo "Mock scp: Download operation from $remote_source to $local_dest"

          # Extract filename from remote path
          local filename=$(basename "${remote_source#*:}")

          # Create signed content based on architecture in path and filename
          if [[ "$remote_source" == *"/amd64/"* ]]; then
            echo "SIGNED_AMD64_MODULE" > "$local_dest/$filename"
          elif [[ "$remote_source" == *"/arm64/"* ]]; then
            echo "SIGNED_ARM64_MODULE" > "$local_dest/$filename"
          else
            # For single architecture, use filename to determine content
            case "$filename" in
              "mod1.ko")
                echo "SIGNED_MODULE1" > "$local_dest/$filename"
                ;;
              "mod2.ko")
                echo "SIGNED_MODULE2" > "$local_dest/$filename"
                ;;
              *)
                echo "SIGNED_MODULE" > "$local_dest/$filename"
                ;;
            esac
          fi
          echo "Mock scp: Created signed file $local_dest/$filename"
        else
          echo "Mock scp: Unable to determine operation type"
        fi
      fi
      ;;
    *)
      echo "Error: Incorrect scp parameters"
      exit 1
      ;;
  esac
}
