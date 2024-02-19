#!/usr/bin/env bash
set -e

function skopeo() {
  echo "Mock skopeo called with: $*" >&2

  # Append call information to mock_skopeo.txt
  echo "$*" >> $(workspaces.data.path)/mock_skopeo.txt

  echo '
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
  "manifests": [
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 1253,
      "digest": "sha256:406a",
      "platform": {
        "architecture": "amd64",
        "os": "linux"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 1252,
      "digest": "sha256:4bfe",
      "platform": {
        "architecture": "arm64",
        "os": "linux"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v1+json",
      "size": 999,
      "digest": "sha256:999",
      "platform": {
        "architecture": "ppc64le",
        "os": "linux"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 1252,
      "digest": "sha256:6f9",
      "platform": {
        "architecture": "ppc64le",
        "os": "linux"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 1253,
      "digest": "sha256:71e1",
      "platform": {
        "architecture": "s390x",
        "os": "linux"
      }
    }
  ]
}'

}
