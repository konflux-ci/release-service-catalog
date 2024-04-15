#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function get-image-architectures() {
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "s390x", "os": "linux"}, "digest": "deadbeef"}'
}
