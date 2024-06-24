#!/usr/bin/env bash
set -eux
# mocks to be injected into task step scripts
export TEST=1

echo "MOCK SETUP"


_TEST_MANIFEST_LIST_OCI_DIGEST="sha256:0000"
_TEST_MANIFEST_LIST_OCI_MDIGEST1="sha256:0000-1"
_TEST_MANIFEST_LIST_OCI_MDIGEST2="sha256:0000-2"
_TEST_MANIFEST_LIST_OCI_MDIGEST3="sha256:0000-3"
_TEST_MANIFEST_LIST_OCI_REFERENCE="quay.io/test-product----test-image0@${_TEST_MANIFEST_LIST_OCI_DIGEST}"
_TEST_MANIFEST_LIST_OCI_REPO="registry.redhat.io/test-product/test-image0"

_TEST_MANIFEST_LIST_DIGEST="sha256:1111"
_TEST_MANIFEST_LIST_MDIGEST1="sha256:1111-1"
_TEST_MANIFEST_LIST_MDIGEST2="sha256:1111-2"
_TEST_MANIFEST_LIST_MDIGEST3="sha256:1111-3"
_TEST_MANIFEST_LIST_REFERENCE="quay.io/test-product----test-image0@${_TEST_MANIFEST_LIST_DIGEST}"
_TEST_MANIFEST_LIST_REPO="registry.redhat.io/test-product/test-image0"

_TEST_MANIFEST_DIGEST="sha256:2222"
_TEST_MANIFEST_REFERENCE="quay.io/test-product----test-image0@${_TEST_MANIFEST_DIGEST}"
_TEST_MANIFEST_REPO="registry.redhat.io/test-product/test-image0"

_CONFIG_MAP=$(cat << EOF
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "test-signing-config-map",
    "namespace": "default",
    "labels": {
    }
  },
  "data": {
    "SIG_KEY": "aws://arn:mykey"
  }
}
EOF
)


_DOCKER_MANIFEST_LIST=$(cat << EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
  "manifests": [
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 528,
      "digest": "${_TEST_MANIFEST_LIST_MDIGEST1}",
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.version": "4.9.0-8-amd64",
        "features": [
          "sse4"
        ]
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 527,
      "digest": "${_TEST_MANIFEST_LIST_MDIGEST2}",
      "platform": {
        "architecture": "arm64",
        "os": "linux",
        "os.version": "4.14.0-115-arm64",
        "variant": "v8"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 526,
      "digest": "${_TEST_MANIFEST_LIST_MDIGEST3}",
      "platform": {
        "architecture": "ppc64le",
        "os": "linux"
      }
    }
  ]
}
EOF
)
_DOCKER_MANIFEST=$(cat << EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "size": 7023,
    "digest": "sha256:ec4e3d3b8f35e01df8b97b23d6530e3d8b69f792b54d3b726d79b8f9e8a27e3c"
  },
  "layers": [
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "size": 32654,
      "digest": "sha256:8c662931926fae64a0e5f21db4bcf6e4c6d29851706e6dd987758a4d8552b7f0"
    },
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "size": 16724,
      "digest": "sha256:16e4f9a1b23b571e7d5e7f241e5f6f1534b933b23f8c4f6e7e4b1e6f5b5f6e5f"
    },
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "size": 73109,
      "digest": "sha256:713c5c50d3d5f6b7f3c5f4e7e7e9b9b5e4b7c3f6e6d4d5f7f6b5f7b7e7b5f6f7"
    }
  ]
}
EOF
)
_DOCKER_MANIFEST_LIST_OCI=$(cat <<EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 707,
      "digest": "${_TEST_MANIFEST_LIST_OCI_MDIGEST1}",
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.version": "4.19.0-12-amd64"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 706,
      "digest": "${_TEST_MANIFEST_LIST_OCI_MDIGEST2}",
      "platform": {
        "architecture": "arm64",
        "os": "linux",
        "os.version": "4.19.0-12-arm64",
        "variant": "v8"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 705,
      "digest": "${_TEST_MANIFEST_LIST_OCI_MDIGEST3}",
      "platform": {
        "architecture": "s390x",
        "os": "linux"
      }
    }
  ],
  "annotations": {
    "org.opencontainers.image.created": "2024-06-21T10:30:00Z",
    "org.opencontainers.image.authors": "Jane Doe <jane.doe@example.com>",
    "org.opencontainers.image.version": "1.0.0"
  }
}
EOF
)



function kubectl_get_arg_from_config_map() {
  echo "$@" >> $(workspaces.data.path)/mock_kubectl_get_arg_from_config_map_calls
  echo "$_CONFIG_MAP" | jq -r ".data.$2" | tr -d \"
}
function run_inspect() {
  echo "$@" >> $(workspaces.data.path)/mock_run_inspect_calls
  if [ "$1" = "docker://${_TEST_MANIFEST_LIST_OCI_REFERENCE}" ]; then
    echo "$_DOCKER_MANIFEST_LIST_OCI" | jq -rc
  elif [ "$1" = "docker://${_TEST_MANIFEST_LIST_REFERENCE}" ]; then
    echo "$_DOCKER_MANIFEST_LIST" | jq -rc
  elif [ "$1" = "docker://${_TEST_MANIFEST_REFERENCE}" ]; then
    echo "$_DOCKER_MANIFEST" | jq -rc
  fi
}
function run_cosign () {
  echo "$@" >> $(workspaces.data.path)/mock_run_cosign_calls
  echo "running cosign: $@"
}
