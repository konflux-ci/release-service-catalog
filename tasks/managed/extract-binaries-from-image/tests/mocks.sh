# mocks to be injected into task step scripts

#!/usr/bin/env bash
set -ex

function skopeo() {
  echo "Mock skopeo called with: $*"
  echo "$*" >> "$(params.dataDir)/mock_skopeo.txt"

  case "$*" in
    "copy --retry-times 3 docker://registry.io/image:tag dir:"* | \
    "copy --retry-times 3 docker://registry.io/image2:tag dir:"* | \
    "copy --retry-times 3 docker://registry.io/image3:tag dir:"*)
      # Extract tar files into the destination directory
      cp $(params.dataDir)/image_data/* $TMP_DIR/
      ;;
    *)
      echo "Error: Unexpected call"
      exit 1
      ;;
  esac
}
