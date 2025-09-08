#!/usr/bin/env bash
set -eux

function skopeo() {
    if [[ "$*" == "inspect --retry-times 3 --raw docker://quay.io/fbc/multi-arch@sha256:index" ]]; then
        echo '{ "mediaType": "application/vnd.oci.image.index.v1+json" }'
    elif [[ "$*" == *"quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component-docker-v2s2"* ]] && \
         [[ "$*" == *"@sha256:dockerv2s2index"* ]]; then
        # Docker v2 schema 2 manifest list format
        echo '{ "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json" }'
    elif [[ "$*" == *"quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component-docker-v2s2"* ]] && \
         [[ "$*" == *"@sha256:dockerv2s2manifest"* ]]; then
        # Docker v2s2 component returns v4.15
        echo '{ "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
                "annotations": {
                  "org.opencontainers.image.base.digest": "sha256:dockerv2s2manifest",
                  "org.opencontainers.image.base.name": "registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.15"
                }
              }'
    elif [[ "$*" == *"quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component"* ]]; then
        # First component returns v4.12
        echo '{ "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "annotations": {
                  "org.opencontainers.image.base.digest": "sha256:manifest",
                  "org.opencontainers.image.base.name": "registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.12"
                }
              }'
    else
        # Second component returns v4.13 to create a mismatch
        echo '{ "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "annotations": {
                  "org.opencontainers.image.base.digest": "sha256:manifest",
                  "org.opencontainers.image.base.name": "registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.13"
                }
              }'
    fi
}

function get-image-architectures() {
    if [[ "$1" == *"test-fbc-component-docker-v2s2"* ]]; then
        # Docker v2s2 manifest handling - return different digest for v2s2 test
        jq -nc '{
            "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
            "digest": "sha256:dockerv2s2manifest",
            "size": 100,
            "platform": {"architecture": "amd64", "os": "linux"}
        }'
        jq -nc '{
            "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
            "digest": "sha256:dockerv2s2manifest", 
            "size": 100,
            "platform": {"architecture": "ppc64le", "os": "linux"}
        }'
    else
        # Default OCI handling
        jq -nc '{
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "digest": "sha256:manifest",
            "size": 100,
            "platform": {"architecture": "amd64", "os": "linux"}
        }'
        jq -nc '{
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "digest": "sha256:manifest",
            "size": 100,
            "platform": {"architecture": "ppc64le", "os": "linux"}
        }'
    fi
}
