#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> $(workspaces.data.path)/mock_cosign.txt

  # mock cosign failing the first 3x for the retry test
  if [[ "$*" == "copy -f registry.io/retry-image:tag "*":"* ]]
  then
    if [[ $(cat $(workspaces.data.path)/mock_cosign.txt | wc -l) -le 3 ]]
    then
      echo Expected cosign call failure for retry test
      return 1
    fi
  fi

  if [[ "$*" != "copy -f "*":"*" "*":"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}

function skopeo() {
  echo Mock skopeo called with: $*
  echo $* >> $(workspaces.data.path)/mock_skopeo.txt

  if [[ "$*" != "inspect --no-tags --format {{.Digest}} docker://"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  # echo the docker:// image string so the task knows if two images are the same
  echo $5
}
