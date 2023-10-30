#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function create_container_image() {
  echo $* >> $(workspaces.data.path)/mock_create_container_image.txt
  echo The image id is 0000

  if [[ "$*" != "--pyxis-url https://pyxis.preprod.api.redhat.com/ --certified false --tag "*" --is-latest false --verbose --skopeo-result /tmp/skopeo-inspect.json --media-type my_media_type --rh-push "* ]]
  then
    echo Error: Unexpected call
    echo Mock create_container_image called with: $*
    exit 1
  fi
}

function skopeo() {
  if [[ "$*" == "inspect --raw docker://"* ]]
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
