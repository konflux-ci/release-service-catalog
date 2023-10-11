# mocks to be injected into task step scripts

#!/bin/sh -ex

function skopeo() {
  echo "Mock skopeo called with: $*"
  echo "$*" >> $(workspaces.data.path)/mock_skopeo.txt

  if [[ "$*" != "copy docker://registry.io/image:tag dir:/"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  cp $(workspaces.data.path)/image_data/* $TMP_DIR/
}
