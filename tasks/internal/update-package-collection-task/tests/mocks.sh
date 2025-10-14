#!/usr/bin/env bash
set -euo pipefail

function git() {
    if [[ "$*" == "clone --depth 1 --branch main https://gitlab.cee.redhat.com/package-collection/package-collection-utils.git ." ]]; then
        echo "Cloning repo..."
    else
        /usr/bin/git "$@"
    fi
    record_call git "$@"
}

function curl() {
    record_call curl "$@"
}

function uv() {
    record_call uv "$@"
}
