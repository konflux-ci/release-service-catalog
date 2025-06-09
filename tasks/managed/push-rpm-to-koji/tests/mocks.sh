#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
    echo "kinit $@" >> "$(workspaces.data.path)/kinit_calls.txt"
    call_count=$(wc -l < "$(workspaces.data.path)/kinit_calls.txt")
    # Simulate kinit failures on first two calls
    if [[ "$call_count" < 3 ]]; then
        echo "kinit failed"
        return 1
    fi
}

function oras() {
    echo "oras $@" >> "$(workspaces.data.path)/oras_calls.txt"
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
        echo '{"annotations": {"koji.build-target": "mock-target"}}'
    elif [[ "$1" == "pull" ]]; then
        touch "cg_import.json"
        touch "test.src.rpm"
    fi
}

function koji() {
    echo "koji $@" >> "$(workspaces.data.path)/koji_calls.txt"
    if [[ "$*" == *CGInitBuild* ]]; then
        echo '{"build_id": 12345, "token": "mock-token"}'
    fi
}
