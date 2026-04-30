#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function select-oci-auth() {
    echo Mock select-oci-auth called with: $*
    echo $* > "$(params.dataDir)/mock_select-oci-auth.txt"

    if [[ "$*" == *"fail-raw-disk-image@sha256:123456" ]]; then
        echo Simulating failed select-oci-auth
        exit 1
    fi
}

function oras() {
    echo Mock oras called with: $*
    echo $* > "$(params.dataDir)/mock_oras.txt"
    pwd > "$(params.dataDir)/mock_oras_workdir.txt"

    if [[ "$*" != "pull --registry-config"* ]]; then
        echo Error: Unexpected call to oras
        exit 1
    fi

    # Simulate downloaded artifact: create a compressed disk image
    # Determine the disk format from the pullspec
    if [[ "$*" == *"azure"* ]]; then
        echo "dummy disk image content" | gzip > disk.vhd.gz
    else
        echo "dummy disk image content" | gzip > disk.raw.gz
    fi
}

function pushsource-ls() {
    # Capture the staged directory contents before running pushsource-ls
    for arg in "$@"; do
        if [[ "$arg" == staged:* ]]; then
            local staged_dir="${arg#staged:}"
            find "$staged_dir" -type f -o -type d | sort > "$(params.dataDir)/mock_staged_dir.txt"
            break
        fi
    done
    command pushsource-ls "$@" 2>&1 | tee "$(params.dataDir)/mock_pushsource_ls.txt"
    return "${PIPESTATUS[0]}"
}

function marketplacesvm_push_wrapper() {
    echo Mock marketplacesvm_push_wrapper called with: $*
    echo $* > "$(params.dataDir)/mock_wrapper.txt"
    echo "$CLOUD_CREDENTIALS" > "$(params.dataDir)/mock_cloud_credentials.txt"

    /home/pubtools-marketplacesvm-wrapper/marketplacesvm_push_wrapper "$@" --dry-run

    if ! [[ "$?" -eq 0 ]]; then
        echo Unexpected call to marketplacesvm_push_wrapper
        exit 1
    fi

    # create fake artifacts which would be created by pubtools-marketplacesvm-marketplace-push
    mkdir -p artifacts/20260430181240/
    touch artifacts/20260430181240/pushitems.jsonl
    touch artifacts/20260430181240/clouds.json
}

