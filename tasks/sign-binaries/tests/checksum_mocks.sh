#!/usr/bin/env bash


count_file="/tmp/ssh_count_checksum.txt"
if [[ ! -f "$count_file" ]]; then
    echo "0" > "$count_file"
fi


function ssh() {
    # Read the current ssh_call_count from the file
    ssh_call_count=$(cat "$count_file")
    ssh_call_count=$((ssh_call_count + 1))
    echo "$ssh_call_count" > "$count_file"
    echo "$ssh_call_count" > $(workspaces.data.path)/ssh_calls_checksum.txt
}

scp_count_file="/tmp/scp_count_checksum.txt"
if [[ ! -f "$scp_count_file" ]]; then
    echo "0" > "$scp_count_file"
fi

function scp() {
    scp_call_count=$(cat "$scp_count_file")
    scp_call_count=$((scp_call_count + 1))
    echo "$scp_call_count" > "$scp_count_file"
    if [[ "$scp_call_count" -eq 1 ]]; then
        echo "$@" > $(workspaces.data.path)/mock_scp_1_checksum.txt
    fi


    if [[ "$scp_call_count" -eq 2 ]]; then
    echo "$@" > "$(workspaces.data.path)/mock_scp_2_checksum.txt"
    echo -n "sha256:0c4355ee4ef8d9d3875d5421972aed405ce6d8f5262983eeea3f6cbf5740c6e2" | \
    tee "$(results.signedWindowsDigest.path)"
    fi

}

function kinit() {
    echo "kinit $@"
}

function oras() {
    oras_args=$@
    echo "Trying to use oras with $oras_args"

    # Check for Windows signing script
    if [[ "$oras_args" == *"pull"* && "$oras_args" == *"signed"* ]]; then
        echo "Trying to pull signed digests: $@"
        mkdir -p "$(workspaces.data.path)/$(params.contentDir)/signed/macos/"
        mkdir -p "$(workspaces.data.path)/$(params.contentDir)/signed/windows/"
        echo -n "some data" | \
        tee "$(workspaces.data.path)/$(params.contentDir)/signed/macos/mac_binary.bin"
        echo -n "some data" | \
        tee "$(workspaces.data.path)/$(params.contentDir)/signed/windows/windows_binary.bin"
    fi
}
