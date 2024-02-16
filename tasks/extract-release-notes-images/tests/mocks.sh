#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function get-image-architectures() {
    echo amd64
    echo s390x
}
