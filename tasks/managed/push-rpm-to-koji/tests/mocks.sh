#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
    echo "kinit $@"
}

function oras() {
    echo "oras $@"
}

function koji() {
    echo "oras $@"
}

function base64() {
    echo "base64 $@"
}
