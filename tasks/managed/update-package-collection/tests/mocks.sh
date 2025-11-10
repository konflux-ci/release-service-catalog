#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function kinit() {
    echo "kinit $*" >> "$(params.dataDir)/kinit_calls.txt"
    call_count=$(wc -l < "$(params.dataDir)/kinit_calls.txt")
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
    if [[ "$*" == *getTag*-sidetag* ]]; then
        echo '{"extra": {"sidetag": true}}'
    elif [[ "$*" == *getTag* ]]; then
        echo '{"extra": {"sidetag": false}}'
    elif [[ "$*" == *buildinfo* ]]; then
        # Simulate build not existing
        echo "No such build: $*" >&2
        return 1
    elif [[ "$*" == *hello* ]]; then
        echo "Hello, mock user!"
    fi
}

function uv() {
    echo "uv $*" >> "$(params.dataDir)/uv_calls.txt"

    if [[ "$*" == *run*package-collection*add-builds* ]]; then
        call_count=$(grep -c "uv run pc-manager package-collection add-builds" "$(params.dataDir)/uv_calls.txt" || true)

        # Fail first two attempts, succeed on third (when max_retries=3)
        if [[ $call_count -lt 3 ]]; then
            echo "Mock uv add-builds failed on attempt $call_count" >&2
            return 1
        else
            echo "Mock package-collection add-builds completed successfully on attempt $call_count"
            return 0
        fi
    elif [[ "$*" == *sync* ]]; then
        echo "Mock uv sync completed"
    fi
}

function git() {
    echo "git $*" >> "$(params.dataDir)/git_calls.txt"
    if [[ "$*" == *clone* ]]; then
        mkdir -p package-collection-utils
        echo "Mock git clone completed"
    elif [[ "$*" == *checkout* ]]; then
        echo "Mock git checkout completed"
    elif [[ "$*" == *config* ]]; then
        echo "Mock git config completed"
    fi
}

function glab() {
  echo "Mock glab called with: $*"

  if [[ "$*" != "auth login"* ]]; then
    echo Error: Unexpected call
    exit 1
  fi
}


function timeout() {
    echo "timeout $*" >> "$(params.dataDir)/timeout_calls.txt"
    # Execute the actual command after timeout
    local duration=$1
    shift
    "$@"
}

function openssl() {
    echo "openssl $*" >> "$(params.dataDir)/openssl_calls.txt"
    if [[ "$*" == *s_client* ]]; then
        echo "-----BEGIN CERTIFICATE-----"
        echo "MOCK CERTIFICATE"
        echo "-----END CERTIFICATE-----"
    fi
}


# Mock source commands for utility functions
function source_utility_functions() {
    echo "source_utility_functions" >> "$(params.dataDir)/source_calls.txt"
}

function gitlab_init() {
    echo "gitlab_init" >> "$(params.dataDir)/gitlab_calls.txt"
}

function git_functions_init() {
    echo "git_functions_init" >> "$(params.dataDir)/git_functions_calls.txt"
}

function git_clone_and_checkout() {
    echo "git_clone_and_checkout $*" >> "$(params.dataDir)/git_clone_and_checkout_calls.txt"
    mkdir -p package-collection-utils
    cd package-collection-utils
    echo "Mock repository cloned and checked out"
}
