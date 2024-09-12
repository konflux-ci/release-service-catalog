#!/bin/bash


count_file="/tmp/ssh_count.txt"
if [[ ! -f "$count_file" ]]; then
    echo "0" > "$count_file"
fi


function ssh() {
    # Read the current ssh_call_count from the file
    ssh_call_count=$(cat "$count_file")
    ssh_call_count=$((ssh_call_count + 1))
    echo "$ssh_call_count" > "$count_file"

    echo "$ssh_call_count" > $(workspaces.data.path)/ssh_calls.txt
    if [[ "$*" == *"digest.txt"* ]]; then
        # this is mocking oras via Windows ssh returning the signed digest
        echo "mocked ssh $@" > $(workspaces.data.path)/mock_ssh_second_call.txt
        echo "sha256:0c4355ee4ef8d9d3875d5421972aed405ce6d8f5262983eeea3f6cbf5740c6e2"
    fi
}

scp_count_file="/tmp/scp_count.txt"
if [[ ! -f "$scp_count_file" ]]; then
    echo "0" > "$scp_count_file"
fi
function scp() {
    scp_call_count=$(cat "$scp_count_file")
    scp_call_count=$((scp_call_count + 1))
    echo "$scp_call_count" > "$scp_count_file"
    if [[ "$scp_call_count" -eq 1 ]]; then
        echo "$@" > $(workspaces.data.path)/mock_scp_1.txt
    fi


    if [[ "$scp_call_count" -eq 2 ]]; then
    echo "$@" > "$(workspaces.data.path)/mock_scp_2.txt"
    echo -n "sha256:0c4355ee4ef8d9d3875d5421972aed405ce6d8f5262983eeea3f6cbf5740c6e2" | \
    tee "$(results.signedWindowsDigest.path)"
    fi

}

function oras() {
    # this is mocking the oras command to push unsigned binaries to the registry
    echo "Digest: sha256:5ce6d8f5262983eeea3f6cbf5740c6e20c4355ee4ef8d9d3875d5421972aed40"
}
