#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function select-oci-auth() {
    echo Mock select-oci-auth called with: $*
}

function oras() {
    echo Mock oras called with: $*
    if [[ "$*" =~ login.* ]]; then
        echo Simulating oras quay login
    elif [[ "$*" =~ push.* ]]; then
        echo Simulating oras push 
        echo "Digest: sha256:$(echo | sha256sum |awk '{ print $1}')"
    elif [[ "$*" == *"nonexistent-disk-image"* ]]; then
        echo Simulating failing oras pull call >&2
        exit 1
    elif [[ "$*" == "pull --registry-config"* ]]; then
        echo "Mocking pulling files"
        touch binary-windows-amd64.zip
        touch binary-darwin-amd64.tar.gz
        touch binary-linux-amd64.tar.gz
    elif [[ "$*" =~ pull.* ]]; then
        echo Simulating oras pull
        mkdir -p windows linux macos
        touch windows/binary-windows-amd64.exe
        touch linux/binary-linux-amd64
        touch macos/binary-darwin-amd64
    fi
    touch fail_gzip.raw.gz
}

# We aren't going to pull real files that can be unzipped, so just remove the .gz suffix on them
function ziputil() {
    echo Mock a compressing tool with: $*
    if [ "$2" == "fail_gzip.raw.gz" ] ; then
        echo gzip failed >&2
        exit 1
    fi

    if [[ "$1" =~ (r|czf)$ ]]; then
        mkdir -p $(dirname $2)
        touch $2
    else
        ext="${2#*.}"
        len=$((${#ext}+1))
        mv "$2" "${2::-${len}}"
    fi
}

function zip() {
    if [[ "$1" =~ (r|czf)$ ]]; then
        ziputil "$@"
    else
        #dnf install zip -y >/dev/null
        ext="${2#*.}"
        len=$((${#ext}+1))
        mv "$2" "${2::-${len}}.exe"
    fi
}

function tar() {
    ziputil "$@"
}

function gzip() {
    ziputil "$@"
}

function pulp_push_wrapper() {
    echo Mock pulp_push_wrapper called with: $*

    if [[ "$*" != *"--pulp-url https://pulp.com"* ]]; then
        printf "Mocked failure of pulp_push_wrapper" > /nonexistent/location
    fi
}

function developer_portal_wrapper() {
  echo Mock developer_portal_wrapper called with: $*

  /home/developer-portal-wrapper/developer_portal_wrapper "$@" --dry-run

  if ! [[ "$?" -eq 0 ]]; then
      echo Unexpected call to developer_portal_wrapper
      exit 1
  fi
}

function ssh() {
    echo Mocking ssh call with: $*
}

function scp() {
    echo Mocking scp call with: $*
    if [[ "$*" =~ .*digest.txt.* ]]; then
        args=($@)
        echo sha256:$(echo | sha256sum |awk '{ print $1}') > ${args[-1]}
    fi
    echo
}

function kinit() {
    echo Mocking kinit call with: $*
    if [ "$*" == "-kt /etc/secrets_keytab/keytab konflux-release-signing-sa@IPA.REDHAT.COM" ] ; then
        echo initialized
    fi
}
