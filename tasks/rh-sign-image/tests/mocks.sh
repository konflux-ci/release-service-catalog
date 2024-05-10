#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  /home/utils/internal-request $@

  sleep 1
  NAME=$(kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
      --sort-by=.metadata.creationTimestamp | tail -1)
  if [ -z $NAME ]; then
      echo Error: Unable to get IR name
      echo Internal requests:
      kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
          --sort-by=.metadata.creationTimestamp
      exit 1
  fi

  if [[ "$*" == *"requester=testuser-failure"* ]]; then
      set_ir_status $NAME Failure 3 &
  elif [[ "$*" == *"requester=testuser-timeout"* ]]; then
      # The interval in wait-for-ir is 5 sec, so increase the ir delay to timeout for sure
      set_ir_status $NAME Succeeded 10 &
  else
      set_ir_status $NAME Succeeded 5 &
  fi
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "reason": "${REASON}",
        "lastTransitionTime": "2023-12-06T15:22:45Z",
        "message": "my message",
        "status": "True",
        "type": "merge"
      }
    ]
  }
}
EOF
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}

function skopeo() {
  echo $* >> $(workspaces.data.path)/mock_skopeo.txt
  if [[ "$*" == "inspect --raw docker://"* ]] || [[ "$*" == "inspect --no-tags --override-os linux --override-arch "*" docker://"* ]]
  then
    echo '{"mediaType": "my_media_type"}'
  else
    echo Mock skopeo called with: $*  >> /dev/stderr
    if [[ "$*" != "inspect --no-tags docker://"* ]]
    then
      if [[ "$*" == "inspect --no-tags --raw docker://registry.io/multi-arch-image0"* ]]
      then
        echo '{
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "manifests": [
                  {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": "sha256:6f9a420f660e73a",
                    "size": 920,
                    "platform": {
                      "architecture": "amd64",
                      "os": "linux"
                    }
                  },
                  {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": "sha256:6f9a420f660e73b",
                    "size": 920,
                    "platform": {
                      "architecture": "arm64",
                      "os": "linux"
                    }
                  }
                ]
              }
            '
      else
        if [[ "$*" == "inspect --no-tags --raw docker://registry.io/image"* ]]
        then
          echo '{
                  "schemaVersion": 2,
                  "mediaType": "application/vnd.oci.image.manifest.v1+json",
                  "config": {
                    "mediaType": "application/vnd.oci.image.config.v1+json",
                    "digest": "sha256:9e8f9c7bdce16d2e9ebf93b84d3f8df9821ab74f8c2bf73446e8828f936c9db1",
                    "size": 11125
                  },
                  "layers": [
                    {
                      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                      "digest": "sha256:b4e744f5f131fb2db0dd7649806f286ecaa3fcda18dc9a4245d83e902100ccb3",
                      "size": 78771642
                    },
                    {
                      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                      "digest": "sha256:73a17d894da5e42b3c7d90bec673fc1a7d35ce351b2dd0fe9b82a5366f224456",
                      "size": 174964243
                    },
                    {
                      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                      "digest": "sha256:f9f79b486e0a53e4257f6d0baeb28bf8d662f5de03997e9eb7ccf658e4069c31",
                      "size": 122857
                    }
                  ],
                  "annotations": {
                    "org.opencontainers.image.base.digest": "sha256:5ee218882a725fe3fcc8ebd803e82a7182dbee47aef0efcaf3852df9ad15347b",
                    "org.opencontainers.image.base.name": "registry.access.redhat.com/ubi8/ubi:8.9-1028"
                  }
                }
            '
        else
          if [[ "$*" == "inspect --no-tags --format {{.Digest}} docker://registry.io/image"*":sha256-"*".src"* ]]
          then
            echo "sha256:9e8f9c7bdce16d2e9ebf93b84d3f8df9821ab74f8c2bf73446e8828f936c9db1"
          else
            echo Error: Unexpected call
            exit 1
          fi
        fi
      fi
    fi
  fi
}
