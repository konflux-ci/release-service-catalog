#!/usr/bin/env bash
set -eux
# mocks to be injected into task step scripts
echo "MOCK SETUP"


_TEST_MANIFEST_LIST_OCI_REFERENCE="quay.io/redhat-user-workloads/test-product/test-image0@sha256:0000"
_TEST_MANIFEST_LIST_REFERENCE="quay.io/redhat-user-workloads/test-product/test-image1@sha256:1111"
_TEST_MANIFEST_REFERENCE="quay.io/redhat-user-workloads/test-product/test-image2@sha256:2222"

_DOCKER_MANIFEST_LIST=$(cat << EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
  "manifests": [
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 528,
      "digest": "sha256:1111-1",
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
      "digest": "sha256:1111-2",
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
      "digest": "sha256:1111-3",
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
      "digest": "sha256:0000-1",
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.version": "4.19.0-12-amd64"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 706,
      "digest": "sha256:0000-2",
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
      "digest": "sha256:0000-3",
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

function skopeo() {
  echo "$@" >> $(workspaces.data.path)/mock_skopeo_calls
  if [ "$1" = "inspect" ]; then
    if [ "$3" = "docker://${_TEST_MANIFEST_LIST_OCI_REFERENCE}" ]; then
      echo "$_DOCKER_MANIFEST_LIST_OCI" | jq -r
    elif [ "$3" = "docker://${_TEST_MANIFEST_LIST_REFERENCE}" ]; then
      echo "$_DOCKER_MANIFEST_LIST" | jq -r
    elif [ "$3" = "docker://${_TEST_MANIFEST_REFERENCE}" ]; then
      echo "$_DOCKER_MANIFEST" | jq -r
    fi
  fi
}
function mktemp() {
  echo "temp_key_file"
}

function cosign () {
  # check if call should end successfully
  # mock_cosign_success_calls file is expected to contain lines with "1" or "0" where
  # "1" means that the call should end successfully and "0" means that the call should end with an error
  # following command pops the first line from the file and stores it in successfull_run variable
  successfull_run=$(sed -n '1p' $(workspaces.data.path)/mock_cosign_success_calls && \
    sed -i '1d' $(workspaces.data.path)/mock_cosign_success_calls)

  if [ "$1" = "verify" ]; then
    mock_existing_sig_file=$(echo "${*: -1}" | tr "/" "-")
    echo "$@" >> $(workspaces.data.path)/mock_cosign_verify_calls
    # if the call shouldn't end successfully, exit with error
    if [ "$successfull_run" != "1" ]; then
      return 1
    fi
    cat "$(workspaces.data.path)/$mock_existing_sig_file"
  else
    echo "running cosign: $@"
    echo "$@" >> "$(workspaces.data.path)/mock_cosign_sign_calls"
    # if the call shouldn't end successfully, exit with error
    if [ "$successfull_run" != "1" ]; then
      >&2 echo "- SIMULATED ERROR -"
      echo "- SIMULATED ERROR -" >> "$(workspaces.data.path)/mock_cosign_sign_calls"
      return 1
    fi
  fi
}
