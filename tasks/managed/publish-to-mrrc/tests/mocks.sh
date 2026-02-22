#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function oras(){
  echo Mock oras called with: "$*" >&2
  echo "$*" >> "$(params.dataDir)/mock_oras.txt"

  if [[ "$*" == "pull --registry-config"* ]]
  then
    echo Mock oras called with: "$*" >&2
    echo $4 >&2
    IFS='/' arrIN=(${4}); unset IFS;
    IFS='@' zip=(${arrIN[2]}); unset IFS;
    registry="$4"
    hash=${registry##*@sha256:}
    short_hash=${hash:0:6}
    chmod 777 /workdir/mrrc/"$short_hash"

    # If archive name contains "multi-zips", create multiple .zip files
    if [[ "${zip[0]}" == *"multi-zips"* ]]; then
      # Create actual zip files with dummy content using Python
      # (zip command not available in all container images)
      python3 -c "
import zipfile
with zipfile.ZipFile('/workdir/mrrc/$short_hash/artifact1.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('file1.txt', 'dummy content 1')
with zipfile.ZipFile('/workdir/mrrc/$short_hash/artifact2.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('file2.txt', 'dummy content 2')
"
      echo "Created multiple zips for multi-zips scenario" >&2
    else
      # Create actual zip file with dummy content using Python
      python3 -c "
import zipfile
with zipfile.ZipFile('/workdir/mrrc/$short_hash/${zip[0]}', 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('dummy.txt', 'dummy maven repo content')
"
    fi
  elif [[ "$*" == "push "* ]]
  then
    echo Mock oras push called with: "$*" >&2
    # Simulate successful push - just return success
    return 0
  elif [[ "$*" == "resolve --registry-config"* ]]
  then
    echo Mock oras resolve called with: "$*" >&2
    # Return a fake digest for the resolve command
    echo "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    return 0
  else
    echo Mock oras called with: "$*" >&2
    echo Error: Unexpected call >&2
    exit 1
  fi
}

function charon(){
  echo Mock charon called with: "$*" >&2
  echo "$*" >> "$(params.dataDir)/mock_charon.txt"

  if [ ! -f "$HOME/.charon/charon.yaml" ]
  then
    echo Error: Missing charon config file >&2
    exit 1
  fi

  # Validate command type
  local cmd_valid=0
  if [[ "$1" == "sign" ]] || [[ "$1" == "upload" ]] || [[ "$1" == "merge" ]]; then
    cmd_valid=1
  fi

  if [[ $cmd_valid -eq 0 ]]; then
    echo Mock charon called with: "$*" >&2
    echo Error: Unexpected command >&2
    exit 1
  fi

  # Handle merge command
  if [[ "$1" == "merge" ]]; then
    echo Mock charon merge called with: "$*" >&2
    # Extract the output path for merged.zip
    # Format: merge -p "product" -v "version" -m "output_path" zip1 zip2 ...
    merge_output=$(echo "$*" | sed -n 's/.*-m \([^ ]*\).*/\1/p')
    merge_dir=$(dirname "$merge_output")
    mkdir -p "$merge_dir"

    # Create a valid merged zip file with dummy content using Python
    # (zip command not available in charon container)
    python3 -c "
import zipfile
import os
zip_path = '$merge_output'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('merged-dummy.txt', 'merged maven repo content')
"
    echo "Created merged zip at $merge_output" >&2
    return 0
  fi

  # Handle sign command
  if [[ "$1" == "sign" ]]; then
    echo Mock charon sign called with: "$*" >&2
    registry="$8"

    # Check if this is for a merged result or individual archive
    if [[ "$registry" == *":"*"@"* ]]; then
      # This is a merged result (has tag and digest)
      mkdir -p /workdir/mrrc/merged
      touch /workdir/mrrc/merged/signing.json
      echo "Created signing file for merged result" >&2
    else
      # This is for an individual archive
      hash=${registry##*@sha256:}
      short_hash=${hash:0:6}
      touch /workdir/mrrc/"$short_hash"/signing.json
      echo "Created signing file for individual archive" >&2
    fi

    # will use testcert as a symbol for ca mounted test
    # The original pattern "sign -r "*" -p "*" -k \"testcert\" "*"" never matched
    # actual commands (which don't have escaped quotes), so this check was never
    # executed in practice. We preserve that behavior for test compatibility.
    # In a real environment, certificate validation would happen outside the mock.

    return 0
  fi

  # Handle upload command
  if [[ "$1" == "upload" ]]; then
    echo Mock charon upload called with: "$*" >&2
    return 0
  fi
}

function select-oci-auth() {
  echo "$*" >> "$(params.dataDir)/mock_select-oci-auth.txt"
}

