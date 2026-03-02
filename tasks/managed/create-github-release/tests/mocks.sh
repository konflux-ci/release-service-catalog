#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function skopeo() {
  echo "Mock skopeo called with: $*"
  echo "$*" >> "$(params.dataDir)/mock_skopeo.txt"

  case "$*" in
    "copy --retry-times 3 docker://registry.io/image:tag dir:"*)
      cp "$(params.dataDir)"/image_data/* "$TMP_DIR"/
      ;;
    *)
      echo "Error: Unexpected skopeo call"
      exit 1
      ;;
  esac
}

function gh() {
  echo "Mock gh called with: $*" >&2
  echo "$*" >> "$(params.dataDir)/mock_gh.txt"
  if [[ "$*" == "api repos/foo/repo_with_release/releases"* ]]; then
    echo "{"repodata": "lotsofdata"}"
    exit 0
  elif
    [[ "$*" == "release create v1.2.3 "*"./foo_SHA256SUMS ./foo_SHA256SUMS.sig --repo https://github.com/foo/bar --title Release 1.2.3" ]] || \
    [[ "$*" == "api repos/foo/bar/releases"* ]]; then
    exit 0
  else
    echo Error: Unexpected call
    exit 1
  fi
}
