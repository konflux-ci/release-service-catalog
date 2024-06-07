#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function create_container_image() {
  echo $* >> $(workspaces.data.path)/mock_create_container_image.txt
  # The image id is a 4 digit number with leading zeros calculated from the call number,
  # e.g. 0001, 0002, 0003...
  echo The image id is $(awk 'END{printf("%04i", NR)}' $(workspaces.data.path)/mock_create_container_image.txt)

  if [[ "$*" != "--pyxis-url https://pyxis.preprod.api.redhat.com/ --certified false --tags "*" --is-latest false --verbose --skopeo-result /tmp/skopeo-inspect.json --media-type my_media_type --architecture-digest "*" --rh-push "* ]]
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
    echo '{"mediaType": "my_media_type"}'
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
  if [[ "$*" =~ registry.io/multi-arch-image.?@mydigest.? ]]; then
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
  else
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
  fi
}
