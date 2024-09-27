# mocks to be injected into task step scripts

#!/usr/bin/env bash
set -ex

function skopeo() {
  echo "Mock skopeo called with: $*"
  echo "$*" >> $(workspaces.data.path)/mock_skopeo.txt

  case "$*" in
    "copy docker://registry.io/image:tag dir:"* | "copy docker://registry.io/image2:tag dir:"* | "copy docker://registry.io/image3:tag dir:"*)
      # Extract tar files into the destination directory
      cp $(workspaces.data.path)/image_data/* $TMP_DIR/
      ;;
    *)
      echo "Error: Unexpected call"
      exit 1
      ;;
  esac
}
