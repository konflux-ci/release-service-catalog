#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
    echo "kinit $*" >> "$(params.dataDir)/kinit_calls.txt"
    call_count=$(wc -l < "$(params.dataDir)/kinit_calls.txt")
    # Simulate kinit failures on first two calls
    if [[ "$call_count" -lt 3 ]]; then
        echo "kinit failed"
        return 1
    fi
}

function mktemp() {
    echo /tmp/foobar
}

function select-oci-auth() {
    echo "select-oci-auth $*" >> "$(params.dataDir)/select_oci_auth_calls.txt"
    # This usually includes some auth details, but we're not really going to use it
    echo "{}"
}

function oras() {
    echo "oras $*" >> "$(params.dataDir)/oras_calls.txt"
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
        if [[ "$3" == *test-bar* ]]; then
            echo '{"annotations": {"koji.build-target": "mock-target-sidetag"}}'
        else
            echo '{"annotations": {"koji.build-target": "mock-target-candidate"}}'
        fi
    elif [[ "$1" == "pull" ]]; then
        build_name=$(sed -e 's_.*\/__' -e 's_@.*__' <<< "$*")
        cat > "cg_import.json" <<EOF
        {
            "metadata_version": 0,
            "build": {
                "name": "$build_name",
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
    echo "koji $*" >> "$(params.dataDir)/koji_calls.txt"
    if [[ "$*" == *CGInitBuild*\"test-foo\"* ]]; then
        echo '{"build_id": 111, "token": "mock-token"}'
    elif [[ "$*" == *CGInitBuild*\"test-bar\"* ]]; then
        echo '{"build_id": 222, "token": "mock-token"}'
    elif [[ "$*" == *CGInitBuild*\"test-baz\"* ]]; then
        echo '{"build_id": 333, "token": "mock-token"}'
    elif [[ "$*" == *getTag*-sidetag* ]]; then
        echo '{"extra": {"sidetag": true}}'
    elif [[ "$*" == *getTag* ]]; then
        echo '{"extra": {"sidetag": false}}'
    fi
}
