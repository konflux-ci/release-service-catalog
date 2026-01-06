#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
    echo "kinit $@" >> "$(params.dataDir)/kinit_calls.txt"
    call_count=$(wc -l < "$(params.dataDir)/kinit_calls.txt")
    # Simulate kinit failures on first two calls
    if [[ "$call_count" < 3 ]]; then
        echo "kinit failed"
        return 1
    fi
}

function mktemp() {
    echo /tmp/foobar
}

function select-oci-auth() {
    echo "select-oci-auth $@" >> "$(params.dataDir)/select_oci_auth_calls.txt"
    # This usually includes some auth details, but we're not really going to use it
    echo "{}"
}

function oras() {
    echo "oras $@" >> "$(params.dataDir)/oras_calls.txt"
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
        echo '{"annotations": {"koji.build-target": "mock-target"}}'
    elif [[ "$1" == "pull" ]]; then
        cat > "cg_import.json" <<EOF
        {
            "metadata_version": 0,
            "build": {
                "name": "libecpg",
                "version": "16.1",
                "release": "10.el10_0",
                "epoch": null
            }
        }
EOF
        touch "test.src.rpm"
    fi
}

function koji() {
    echo "koji $@" >> "$(params.dataDir)/koji_calls.txt"
    if [[ "$*" == *listBuilds*source=git+https://gitlab.example.com/rpms/test-foo* ]]; then
        echo '[{"build_id": 1002, "creation_time": "2025-01-01 01:00:00.000000"}, {"build_id": 1001, "creation_time": "2025-01-01 00:00:00.000000"}]'
    elif [[ "$*" == *listBuilds*source=git+https://gitlab.example.com/rpms/test-bar* ]]; then
        echo '[{"build_id": 2001, "creation_time": "2025-01-01 00:00:00.000000"}]'
    fi
}
