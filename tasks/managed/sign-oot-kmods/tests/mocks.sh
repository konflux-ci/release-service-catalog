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
      # Handle find commands for getting recursive file lists
      if [[ "$*" == *"cd ~/"*"/kmods"* && "$*" == *"find . -name '*.ko' -type f"* ]]; then
        echo "Mock ssh: Finding .ko files recursively for download"
        # Return the recursive list of .ko files that should be available after signing
        # Architecture is already captured in the directory path, so filenames don't need arch prefixes
        echo "./mod1.ko"
        echo "./mod2.ko"
        echo "./driversA/driverA-mod1.ko"
        echo "./driversA/driverA-mod2.ko"
        echo "./driversB/driverB-mod1.ko"
        echo "./driversB/submodule/submodule.ko"
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
    "-f /tmp/"*".tar.gz")
      # Handle cleanup of temporary tarball files from recursive implementation
      echo "Mock rm: Cleaning up temporary tarball"
      /bin/rm "$@"
      ;;
    "-rf /tmp/tmp."*)
      # Handle cleanup of temporary directories created by mock scp
      echo "Mock rm: Cleaning up temporary directory"
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
      local args
      read -ra args <<< "$*"

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
          local filename
          filename=$(basename "${remote_source#*:}")

          # Handle tarball downloads for recursive directory structure
          if [[ "$filename" == *.tar.gz ]]; then
            echo "Mock scp: Downloading tarball with recursive structure"
            # Create a temporary tarball with signed files that preserves directory structure
            temp_extract_dir=$(mktemp -d)

            # Create the directory structure with signed files
            mkdir -p "$temp_extract_dir"
            mkdir -p "$temp_extract_dir/driversA"
            mkdir -p "$temp_extract_dir/driversB"
            mkdir -p "$temp_extract_dir/driversB/submodule"

            # Create signed files with original names (architecture already captured in path)
            echo "SIGNED_MODULE1" > "$temp_extract_dir/mod1.ko"
            echo "SIGNED_MODULE2" > "$temp_extract_dir/mod2.ko"
            echo "SIGNED_DRIVER_A_MODULE1" > "$temp_extract_dir/driversA/driverA-mod1.ko"
            echo "SIGNED_DRIVER_A_MODULE2" > "$temp_extract_dir/driversA/driverA-mod2.ko"
            echo "SIGNED_DRIVER_B_MODULE1" > "$temp_extract_dir/driversB/driverB-mod1.ko"
            echo "SIGNED_DRIVER_B_SUBMODULE" > "$temp_extract_dir/driversB/submodule/submodule.ko"

            # Create the tarball
            (cd "$temp_extract_dir" && tar -czf "$local_dest" .)
            rm -rf "$temp_extract_dir"
            echo "Mock scp: Created tarball with signed files at $local_dest"
            return 0
          fi

          # Handle individual file downloads - architecture is already captured in path
          case "$filename" in
            "mod1.ko")
              echo "SIGNED_MODULE1" > "$local_dest/$filename"
              ;;
            "mod2.ko")
              echo "SIGNED_MODULE2" > "$local_dest/$filename"
              ;;
            "driverA-mod1.ko")
              echo "SIGNED_DRIVER_A_MODULE1" > "$local_dest/$filename"
              ;;
            "driverA-mod2.ko")
              echo "SIGNED_DRIVER_A_MODULE2" > "$local_dest/$filename"
              ;;
            "driverB-mod1.ko")
              echo "SIGNED_DRIVER_B_MODULE1" > "$local_dest/$filename"
              ;;
            "submodule.ko")
              echo "SIGNED_DRIVER_B_SUBMODULE" > "$local_dest/$filename"
              ;;
            *)
              echo "SIGNED_MODULE" > "$local_dest/$filename"
              ;;
          esac
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
