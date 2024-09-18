#!/usr/bin/env bash
set -eux

function oras() {
    echo "sha256:manifest"
}

function skopeo() {
    if [[ "$*" == "inspect --raw docker://quay.io/fbc/multi-arch@sha256:index" ]]; then
        echo '{ "mediaType": "application/vnd.oci.image.index.v1+json" }'
    else
        echo '{ "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "annotations": {
                  "org.opencontainers.image.base.digest": "sha256:manifest",
                  "org.opencontainers.image.base.name": "registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.12"
                }
              }'
    fi
}

function get-image-architectures() {
    echo '{"platform":{"digest": "sha256:manifest", "architecture": "amd64", "os": "linux"}}'
    echo '{"platform":{"digest": "sha256:manifest", "architecture": "ppc64le", "os": "linux"}}'
}
