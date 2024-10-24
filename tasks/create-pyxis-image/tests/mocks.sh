#!/usr/bin/env bash
set -exo pipefail

# mocks to be injected into task step scripts

function create_container_image() {
  echo $* >> $(workspaces.data.path)/mock_create_container_image.txt
  # The image id is a 4 digit number with leading zeros calculated from the call number,
  # e.g. 0001, 0002, 0003...
  echo The image id is $(awk 'END{printf("%04i", NR)}' $(workspaces.data.path)/mock_create_container_image.txt)

  if [[ "$*" != "--pyxis-url https://pyxis.preprod.api.redhat.com/ --certified false --tags "*" --is-latest false --verbose --oras-manifest-fetch /workspace/data/oras-manifest-fetch.json --name "*" --media-type my_media_type+gzip --digest "*" --architecture-digest "*" --architecture "*" --rh-push "* ]]
  then
    echo Error: Unexpected call
    echo Mock create_container_image called with: $*
    exit 1
  fi
}

function cleanup_tags() {
  echo $* >> $(workspaces.data.path)/mock_cleanup_tags.txt

  if [[ "$*" != "--verbose --retry --pyxis-graphql-api https://graphql-pyxis.preprod.api.redhat.com/graphql/ "00?? ]]
  then
    echo Error: Unexpected call
    echo Mock cleanup_tags called with: $*
    exit 1
  fi
}

function skopeo() {
  echo $* >> $(workspaces.data.path)/mock_skopeo.txt
  if [[ "$*" == "inspect --raw docker://"* ]] || [[ "$*" == "inspect --no-tags --override-os linux --override-arch "*" docker://"* ]]
  then
    echo '{"mediaType": "my_media_type+gzip"}'
  else
    echo Mock skopeo called with: $*
    if [[ "$*" != "inspect --no-tags docker://"* ]]
    then
      echo Error: Unexpected call
      exit 1
    fi
  fi
}

function get-image-architectures() {
  if [[ "$*" =~ registry.io/multi-arch-image.?@sha256:mydigest.? ]]; then
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
  else
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
  fi
}

function select-oci-auth() {
  echo $* >> $(workspaces.data.path)/mock_select-oci-auth.txt
}

function oras() {
  echo $* >> $(workspaces.data.path)/mock_oras.txt
  if [[ "$*" == "manifest fetch --registry-config"*.dockerfile ]]
  then
    echo '{"layers": [{"annotations": {"org.opencontainers.image.title": "Dockerfile.custom"}}]}'
  elif [[ "$*" == "blob fetch --registry-config"*"/tmp/oras-blob-fetch-beef.gz"* ]]
  then
    echo -n 'H4sIAAAAAAAAA0vKzEssqlRISSxJVEjPTy1WyEgtSgUAXVhZVxUAAAA=' | base64 -d > /tmp/oras-blob-fetch-beef.gz
  elif [[ "$*" == "blob fetch --registry-config"*"/tmp/oras-blob-fetch-pork.gz"* ]]
  then
    echo -n 'H4sIAAAAAAAAA8vNL0pVSEksSQQA2pxWLAkAAAA=' | base64 -d > /tmp/oras-blob-fetch-pork.gz
  elif [[ "$*" == "manifest fetch --registry-config"*image-with-gzipped-layers* ]]
  then
    echo '{"mediaType": "my_media_type", "layers": [{"mediaType": "blob+gzip", "digest": "beef"}, {"mediaType": "blob+gzip", "digest": "pork"}]}'
  elif [[ "$*" == "manifest fetch --registry-config"* ]]
  then
    echo '{"mediaType": "my_media_type", "layers": [{"mediaType": "blob+other", "digest": "tofu"}]}'
  elif [[ "$*" == "pull --registry-config"*dockerfile-not-found:sha256-*.dockerfile* ]]
  then
    echo Mock oras called with: $*
    return 1
  elif [[ "$*" == "pull --registry-config"*dockerfile-file-missing:sha256-*.dockerfile* ]]
  then
    echo Mock oras called with: $*
  elif [[ "$*" == "pull --registry-config"*":sha256-"*.dockerfile* ]]
  then
    echo Mock oras called with: $*
    echo mydocker > $6/Dockerfile.custom
  else
    echo Mock oras called with: $*
    echo Error: Unexpected call
    exit 1
  fi
}
