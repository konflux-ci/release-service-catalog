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

    # Layered images have no titled OCI blob; oras pull must not create the file.
    if [[ "$*" == *"layered-"* ]]; then
        return 0
    fi

    # Simulate downloaded artifact: create a compressed disk image
    # Determine the disk format from the pullspec
    if [[ "$*" == *"azure"* ]]; then
        echo "dummy disk image content" | gzip > disk.vhd.gz
    else
        echo "dummy disk image content" | gzip > disk.raw.gz
    fi
}

function skopeo() {
    echo Mock skopeo called with: $*
    echo $* >> "$(params.dataDir)/mock_skopeo.txt"

    if [[ "$1" != "copy" || "$*" != *"dir:"* ]]; then
        echo Error: Unexpected call to skopeo
        exit 1
    fi
    if [[ "$*" != *"layered-"* ]]; then
        echo Error: Unexpected skopeo pullspec
        exit 1
    fi
    if [[ "$*" == *"layered-skopeo-fail"* ]]; then
        echo Error: simulating skopeo copy failure
        exit 1
    fi

    local dest=""
    for arg in "$@"; do
        if [[ "$arg" == dir:* ]]; then
            dest="${arg#dir:}"
        fi
    done
    if [ -z "${dest}" ]; then
        echo Error: skopeo copy missing dir: destination
        exit 1
    fi

    # skopeo dir transport: manifest.json + blob named by sha256 hex
    local blob="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local missing_blob="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    mkdir -p "${dest}"
    local layer_src
    layer_src=$(mktemp -d)
    mkdir -p "${layer_src}/releases"
    if [[ "$*" == *"layered-missing"* ]]; then
        echo "unrelated layer content" > "${layer_src}/releases/other.raw"
        tar -C "${layer_src}" -czf "${dest}/${blob}" releases/other.raw
        jq -n --arg digest "sha256:${blob}" '{"layers":[{"digest":$digest}]}' \
            > "${dest}/manifest.json"
    elif [[ "$*" == *"layered-uncompressed"* ]]; then
        # Uncompressed layer, docker-style ./ prefix, and a missing first blob.
        echo "dummy disk image content" > "${layer_src}/releases/test-disk-image.raw"
        tar -C "${layer_src}" -cf "${dest}/${blob}" ./releases/test-disk-image.raw
        jq -n \
            --arg missing "sha256:${missing_blob}" \
            --arg digest "sha256:${blob}" \
            '{"layers":[{"digest":$missing},{"digest":$digest}]}' > "${dest}/manifest.json"
    else
        echo "dummy disk image content" > "${layer_src}/releases/test-disk-image.raw"
        tar -C "${layer_src}" -czf "${dest}/${blob}" releases/test-disk-image.raw
        jq -n --arg digest "sha256:${blob}" '{"layers":[{"digest":$digest}]}' \
            > "${dest}/manifest.json"
    fi
    rm -rf "${layer_src}"
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

