#!/usr/bin/env bash
set -euo pipefail

function oras() {
    if [[ "$1" == "pull" ]]; then
        # The auth file path is random, so we can't match the full command.
        # Instead, we'll just check the parts we care about.
        if [[ "$2" == "--registry-config" && "$4" == "quay.io/test/test@sha256:12345" ]]; then
            mkdir -p temp
            touch temp/test-package-1.0-1.src.rpm
            cat > temp/cg_import.json <<EOF
{
    "build": {
        "name": "test-package"
    }
}
EOF
            # The script expects the auth file to be created by select-oci-auth
            # so we need to create it here.
            echo "{}" > "$3"
        fi
    elif [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
        if [[ "$3" == "quay.io/test/test@sha256:12345" && "$4" == "--registry-config" ]]; then
            echo '{"annotations":{"koji.build-target":"test-target"}}'
        fi
    fi
    record_call oras "$@"
}

function internal-request() {
    record_call internal-request "$@"
    echo "InternalRequest 'test-request' created"
}

function kubectl() {
    if [[ "$*" == "get internalrequest test-request -o=jsonpath='{.status.results}'" ]]; then
        echo '{"result": "Success"}'
    fi
    record_call kubectl "$@"
}

function select-oci-auth() {
    # The script redirects the output of this command to a file, so we need to
    # create a mock auth file.
    echo "{}" > /tmp/mock-authfile
    record_call select-oci-auth "$@"
}
