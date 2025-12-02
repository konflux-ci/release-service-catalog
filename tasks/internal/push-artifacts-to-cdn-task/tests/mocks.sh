#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function select-oci-auth() {
    echo Mock select-oci-auth called with: $*
}

function skopeo() {
    echo Mock skopeo called with: $*
    if [[ "$*" =~ copy.*--retry-times.* ]]; then
        # Extract destination directory from skopeo copy command
        # Format: skopeo copy --retry-times 3 --authfile FILE docker://IMAGE dir:DEST
        local args=($*)
        local dest_dir=""
        
        # Find the dir: argument
        for arg in "${args[@]}"; do
            if [[ "$arg" =~ ^dir: ]]; then
                dest_dir="${arg#dir:}"
                break
            fi
        done
        
        if [ -z "$dest_dir" ]; then
            echo "Error: Could not find destination directory in skopeo command" >&2
            exit 1
        fi

        # Check if this is for nonexistent-disk-image and fail
        if [[ "$*" == *"nonexistent-disk-image"* ]]; then
            echo "Simulating failing skopeo copy" >&2
            exit 1
        fi

        echo "Simulating skopeo copy to $dest_dir"
        mkdir -p "$dest_dir"
        cd "$dest_dir"
        
        # Create manifest.json with mock layer digests
        cat > manifest.json << EOF
{
  "layers": [
    {"digest": "sha256:abc123456789"},
    {"digest": "sha256:def456789012"}
  ]
}
EOF
        
        # Create temporary directory structure for releases
        mkdir -p temp_releases/releases
        
        # Create mock binary files based on the container image being pulled
        # All files are .tar.gz since that's the expected source format
        # Create actual tar.gz files with mock binary content inside
        
        create_mock_tgz() {
            local filename="$1"
            local binary_name="${filename%.tar.gz}"
            
            # Create a temporary directory for this binary
            local temp_bin_dir=$(mktemp -d)
            # Create mock binary file
            echo "Mock binary content for $binary_name" > "$temp_bin_dir/$binary_name"
            chmod +x "$temp_bin_dir/$binary_name"
            
            # Create tar.gz file with the mock binary
            tar -czf "temp_releases/releases/$filename" -C "$temp_bin_dir" "$binary_name"
            rm -rf "$temp_bin_dir"
        }
        
        if [[ "$*" =~ ghijkl67890 ]]; then
            # Second test component
            create_mock_tgz "testproduct2-binary-windows-amd64.tar.gz"
            create_mock_tgz "testproduct2-binary-darwin-amd64.tar.gz"
            create_mock_tgz "testproduct2-binary-linux-amd64.tar.gz"
        elif [[ "$*" =~ abelml6910 ]]; then
            # Third test component
            create_mock_tgz "testproduct3-binary-windows-amd64.tar.gz"
            create_mock_tgz "testproduct3-binary-darwin-amd64.tar.gz"
            create_mock_tgz "testproduct3-binary-linux-amd64.tar.gz"
        else
            # Default test component (abcdef12345 or any other SHA)
            create_mock_tgz "testproduct-binary-windows-amd64.tar.gz"
            create_mock_tgz "testproduct-binary-darwin-amd64.tar.gz"
            create_mock_tgz "testproduct-binary-linux-amd64.tar.gz"
        fi
        
        
        # Create real tar files with the releases directory
        tar -czf abc123456789 -C temp_releases releases
        tar -czf def456789012 -C temp_releases releases
        
        # Clean up temp directory
        rm -rf temp_releases
    else
        # Handle other skopeo commands (ensure we don't fall through to real skopeo)
        echo "Mock skopeo: Unhandled command pattern: $*"
        return 0
    fi
}

function oras() {
    echo Mock oras called with: $*
    if [[ "$*" =~ login.* ]]; then
        echo Simulating oras quay login
    elif [[ "$*" =~ push.* ]]; then
        echo Simulating oras push
        echo "Digest: sha256:$(echo | sha256sum |awk '{ print $1}')"
    elif [[ "$*" == *"nonexistent-disk-image"* ]]; then
        echo Simulating failing oras pull call >&2
        exit 1
    elif [[ "$*" == "pull --registry-config"* ]]; then
        echo "Mocking pulling files"
        if [[ "$4" =~ "ghijkl67890" ]]; then
            touch testproduct2-binary-windows-amd64.zip
            touch testproduct2-binary-darwin-amd64.tar.gz
            touch testproduct2-binary-linux-amd64.tar.gz
        fi

        if [[ "$4" =~ "abelml6910" ]]; then
            touch testproduct3-binary-windows-amd64.zip
            touch testproduct3-binary-darwin-amd64.tar.gz
            touch testproduct3-binary-linux-amd64.tar.gz
        fi

        touch testproduct-binary-windows-amd64.zip
        touch testproduct-binary-darwin-amd64.tar.gz
        touch testproduct-binary-linux-amd64.tar.gz
    elif [[ "$*" =~ pull.*-o.* ]]; then
        # Handle oras pull with -o output directory (used for signed binaries)
        echo Simulating oras pull with output directory
        local output_dir=""
        local args=($*)
        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "-o" ]]; then
                output_dir="${args[$((i+1))]}"
                break
            fi
        done
        if [[ -n "$output_dir" ]]; then
            mkdir -p "$output_dir"
            # Determine component from the pull URL
            if [[ "$*" =~ testproduct2/signed ]]; then
                touch "$output_dir/testproduct2-binary-darwin-amd64"
                touch "$output_dir/testproduct2-binary-windows-amd64.exe"
            elif [[ "$*" =~ testproduct3/signed ]]; then
                touch "$output_dir/testproduct3-binary-darwin-amd64"
                touch "$output_dir/testproduct3-binary-windows-amd64.exe"
            else
                touch "$output_dir/testproduct-binary-darwin-amd64"
                touch "$output_dir/testproduct-binary-windows-amd64.exe"
            fi
        fi
    elif [[ "$*" =~ pull.* ]]; then
        echo Simulating oras pull
        # Determine component from the pull URL and create appropriate files
        if [[ "$*" =~ testproduct2/signed ]] || [[ "$*" =~ testproduct2/unsigned ]]; then
            mkdir -p windows macos
            touch windows/testproduct2-binary-windows-amd64.exe
            touch macos/testproduct2-binary-darwin-amd64
        elif [[ "$*" =~ testproduct3/signed ]] || [[ "$*" =~ testproduct3/unsigned ]]; then
            mkdir -p windows macos
            touch windows/testproduct3-binary-windows-amd64.exe
            touch macos/testproduct3-binary-darwin-amd64
        else
            mkdir -p windows macos
            touch windows/testproduct-binary-windows-amd64.exe
            touch macos/testproduct-binary-darwin-amd64
        fi
    fi
}

# Note: We now use real tar, gzip, zip commands instead of mocks for most cases
# The skopeo mock above creates real tar files that these utilities can work with

function pulp_push_wrapper() {
    echo Mock pulp_push_wrapper called with: $*

    if [[ "$*" != *"--pulp-url https://pulp.com"* ]]; then
        printf "Mocked failure of pulp_push_wrapper" > /nonexistent/location
    fi
}

function rsync() {
    echo Mock rsync called with: $*

    if [[ "$3" = "testproduct3-binary-linux-amd64.tar.gz" ]]; then
        printf "Mocked failure of exodus-rsync"
        exit 1
    fi
}

function publish_to_cgw_wrapper() {
  echo "Mock publish_to_cgw_wrapper called with: $*"

  /home/publish-to-cgw-wrapper/publish_to_cgw_wrapper "$@" --dry_run

  if [[ "$?" -ne 0 ]]; then
    echo "Unexpected failure in publish_to_cgw_wrapper dry-run"
    exit 1
  fi
}

function ssh() {
    echo Mocking ssh call with: $*
}

function scp() {
    echo Mocking scp call with: $*
    # Handle digest file copies - write mock digest to destination
    if [[ "$*" =~ .*digest.txt.* ]] || [[ "$*" =~ .*_digest.txt ]]; then
        args=($@)
        dest="${args[-1]}"
        echo sha256:$(echo | sha256sum |awk '{ print $1}') > "$dest"
    fi
    echo
}

function kinit() {
    echo Mocking kinit call with: $*
    # Accept any kinit call with -kt flag as the user and host are now dynamic
    if [[ "$*" == *"-kt"* ]] ; then
        echo initialized
    fi
}

# The retry script won't see the kinit function unless we export it
export -f kinit
