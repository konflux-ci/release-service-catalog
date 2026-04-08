#!/usr/bin/env bash
# Mock skopeo for integration tests (prepended by pre-apply-task-hook.sh).
skopeo() {
  if [[ "${1:-}" == "inspect" ]]; then
    local image_ref="${*##*docker://}"
    if [[ "$image_ref" == *"/myimage@"* ]]; then
      cat <<'MOCKJSON'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "size": 200
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "size": 5000
    }
  ]
}
MOCKJSON
    else
      cat <<'MOCKJSON'
{
  "schemaVersion": 2,
  "config": {
    "mediaType": "application/vnd.cncf.helm.config.v1+json",
    "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "size": 100
  },
  "layers": [],
  "annotations": {
    "org.opencontainers.image.title": "mychart",
    "org.opencontainers.image.version": "1.0.0+buildmeta"
  }
}
MOCKJSON
    fi
    return 0
  fi
  echo "unexpected skopeo invocation: $*" >&2
  exit 1
}
