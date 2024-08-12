#!/usr/bin/env bash
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

  if [[ "$*" == "copy -f private-registry.io/image:tag "*":"* ]]
  then
    if [[ $(cat /etc/ssl/certs/ca-custom-bundle.crt) != "mycert" ]]
    then
      echo Custom certificate not mounted
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
  echo Mock skopeo called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_skopeo.txt

  if [[ "$*" == "inspect --raw docker://"* ]]
  then
    echo '{"mediaType": "my_media_type"}'
    return
  fi

  # If neither of the above matched, it's an unexpected call
  echo Error: Unexpected call
  exit 1
}

function get-image-architectures() {
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
}

function select-oci-auth() {
  echo $* >> $(workspaces.data.path)/mock_select-oci-auth.txt
}

function oras() {
  echo $* >> $(workspaces.data.path)/mock_oras.txt
  if [[ "$*" == "resolve --registry-config "*" "* ]]
  then
    if [[ "$4" == *skip-image*.src || "$4" == *skip-image*-source ]]; then
      echo "sha256:000000"
    elif [[ "$4" == *skip-image* ]]; then
      echo "sha256:111111"
    else
      # echo the shasum computed from the pull spec so the task knows if two images are the same
      echo -n "sha256:"
      echo $4 | sha256sum | cut -d ' ' -f 1
    fi
    return
  else
    echo Mock oras called with: $*
    echo Error: Unexpected call
    exit 1
  fi
}
