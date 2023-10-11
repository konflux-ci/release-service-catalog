# mocks to be injected into task step scripts

set -x

function skopeo() {
  echo "Mock skopeo called with: $*"
  echo "$*" >> $(workspaces.data.path)/mock_skopeo.txt

  if [[ "$*" != "copy docker://registry.io/image:tag dir:/"* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi

  cp $(workspaces.data.path)/image_data/* $TMP_DIR/

#   cat > $TMP_DIR/manifest.json << EOF
#   {
#     "layers": [
#       {"digest": "sha256:1111"},
#       {"digest": "sha256:2222"}
#     ]
#   }
# EOF

#   TAR_IN1=$(mktemp -d)
#   TAR_IN2=$(mktemp -d)

#   mkdir -p $TAR_IN1/$IMAGE_PATH
#   echo text1 > $TAR_IN1/$IMAGE_PATH/file1.txt
#   tar czf $TMP_DIR/1111 -C $TAR_IN1 $IMAGE_PATH
#   echo Files in 1111:
#   tar tzf $TMP_DIR/1111

#   mkdir -p $TAR_IN2/$IMAGE_PATH
#   echo text2 > $TAR_IN2/$IMAGE_PATH/file2.txt
#   tar czf $TMP_DIR/2222 -C $TAR_IN2 $IMAGE_PATH
#   echo Files in 2222:
#   tar tzf $TMP_DIR/2222
}
