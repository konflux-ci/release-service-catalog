#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function date() {
  echo $* >> $(workspaces.config.path)/mock_date.txt

  case "$*" in
      *"2024-07-29T02:17:29 +%Y-%m-%d")
          echo "2024-07-29"
          ;;
      *"+%Y%m%d %T")
          echo "19800101 00:00:00"
          ;;
      *"+%s")
          echo "315550800"
          ;;
      *"+%Y-%m-%d")
          echo "1980-01-01"
          ;;
      *"+%Y-%m")
          echo "1980-01"
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}

function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> $(workspaces.config.path)/mock_skopeo.txt

  if [[ "$*" == "inspect --no-tags --override-os linux --override-arch amd64 docker://registry.io/badimage"* ]]
  then
    echo '{"Labels": {"not-a-build-date": "2024-07-29T02:17:29"}}'
    return
  elif [[ "$*" == "inspect --no-tags --override-os linux --override-arch amd64 docker://registry.io/labels"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29", "Goodlabel": "labelvalue", "Goodlabel-with-dash": "labelvalue-with-dash", "Badlabel": "label with space"}}'
    return
  elif [[ "$*" == "inspect --no-tags --override-os linux --override-arch amd64 docker://registry.io/onlycreated"* ]]
  then
    echo '{"Labels": {"not-a-build-date": "2024-07-29T02:17:29"}, "Created": "2024-07-29T02:17:29"}'
    return
  elif [[ "$*" == "inspect --no-tags --override-os linux --override-arch amd64 docker://"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29"}}'
    return
  fi

  echo Error: Unexpected call
  exit 1
}

function get-image-architectures() {
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
}
