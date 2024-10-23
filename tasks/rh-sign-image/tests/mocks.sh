#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function internal-pipelinerun() {
  TIMEOUT=30
  END_TIME=$(date -ud "$TIMEOUT seconds" +%s)

  echo Mock internal-pipelinerun called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-pipelinerun.txt

  # since we put the PLR in the background, we need to be able to locate it so we can
  # get the name to patch it. We do this by tacking on another random label that we can use
  # to select with later.
  rando=$(openssl rand -hex 12)
  /home/utils/internal-pipelinerun $@ -l "internal-services.appstudio.openshift.io/test-id=$rando" &

  sleep 2
  NAME=
  while [[ -z ${NAME} ]]; do
    if [ "$(date +%s)" -gt "$END_TIME" ]; then
        echo "ERROR: Timeout while waiting to locate PipelineRun"
        echo "Internal pipelineruns:"
        kubectl get pr --no-headers -o custom-columns=":metadata.name" \
            --sort-by=.metadata.creationTimestamp
        exit 124
    fi

    NAME=$(kubectl get pr -l "internal-services.appstudio.openshift.io/test-id=$rando" \
        --no-headers -o custom-columns=":metadata.name" \
        --sort-by=.metadata.creationTimestamp | tail -1)
    if [ -z $NAME ]; then
        echo "Warning: Unable to get PLR name"
        sleep 2
    fi
  done
  echo "PLR Name: $NAME"

  if [[ "$*" == *"requester=testuser-failure"* ]]; then
      set_plr_status $NAME Failure 5
  elif [[ "$*" == *"requester=testuser-timeout"* ]]; then
      echo "skipping setting PLR status since we want a timeout..."
  else
      set_plr_status $NAME Succeeded 5
  fi
  wait -n
}

function set_plr_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    status="True"
    if [ "${REASON}" == "Failure" ]; then
      status="False"
    fi
    cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
     {
        "lastTransitionTime": "2024-10-11T00:23:10Z",
        "message": "Tasks Completed: 4 (Failed: 0, Cancelled 0), Skipped: 0",
        "reason": "${REASON}",
        "status": "${status}",
        "type": "Succeeded"
     }
    ]
  }
}
EOF
    echo "Calling kubectl patch for $NAME..."
    kubectl patch pr $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}

function internal-request() {
  TIMEOUT=30
  END_TIME=$(date -ud "$TIMEOUT seconds" +%s)

  echo Mock internal-request called with: $*
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  # since we put the IR in the background, we need to be able to locate it so we can
  # get the name to patch it. We do this by tacking on another random label that we can use
  # to select with later.
  rando=$(openssl rand -hex 12)
  /home/utils/internal-request $@ -l "internal-services.appstudio.openshift.io/test-id=$rando" &

  sleep 2
  NAME=
  while [[ -z ${NAME} ]]; do
    if [ "$(date +%s)" -gt "$END_TIME" ]; then
        echo "ERROR: Timeout while waiting to locate InternalRequest"
        echo "Internal requests:"
        kubectl get internalrequest --no-headers -o custom-columns=":metadata.name" \
            --sort-by=.metadata.creationTimestamp
        exit 124
    fi

    NAME=$(kubectl get internalrequest -l "internal-services.appstudio.openshift.io/test-id=$rando" \
        --no-headers -o custom-columns=":metadata.name" \
        --sort-by=.metadata.creationTimestamp | tail -1)
    if [ -z $NAME ]; then
        echo "Warning: Unable to get IR name"
        sleep 2
    fi
  done
  echo "IR Name: $NAME"

  if [[ "$*" == *"requester=testuser-failure"* ]]; then
      set_ir_status $NAME Failure 5
  elif [[ "$*" == *"requester=testuser-timeout"* ]]; then
      echo "skipping setting IR status since we want a timeout..."
  else
      set_ir_status $NAME Succeeded 5
  fi
  wait -n
}

function set_ir_status() {
    NAME=$1
    REASON=$2
    DELAY=$3
    echo Setting status of $NAME to reason $REASON in $DELAY seconds... >&2
    sleep $DELAY
    PATCH_FILE=$(workspaces.data.path)/${NAME}-patch.json
    status="True"
    if [ "${REASON}" == "Failure" ]; then
      status="False"
    fi
    cat > $PATCH_FILE << EOF
{
  "status": {
    "conditions": [
      {
        "reason": "${REASON}",
        "lastTransitionTime": "2023-12-06T15:22:45Z",
        "message": "my message",
        "status": "${status}",
        "type": "merge"
      }
    ]
  }
}
EOF
    echo "Calling kubectl patch for $NAME..."
    kubectl patch internalrequest $NAME --type=merge --subresource status --patch-file $PATCH_FILE
}

function skopeo() {
  echo $* >> $(workspaces.data.path)/mock_skopeo.txt
  echo Mock skopeo called with: $*  >> /dev/stderr
  if [[ "$*" == "inspect --raw docker://"* ]] || [[ "$*" == "inspect --no-tags --override-os linux --override-arch "*" docker://"* ]]
  then
    echo '{"mediaType": "my_media_type"}'
  else
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

function select-oci-auth() {
  echo $* >> $(workspaces.data.path)/mock_select-oci-auth.txt
}

function oras() {
  echo $* >> $(workspaces.data.path)/mock_oras.txt
  echo Mock oras called with: $*  >> /dev/stderr
  if [[ "$*" == "resolve --registry-config "*" registry.io/multi-arch-image0"* ]]
  then
    echo 'sha256:6f9a420f660e73a'
    return
  else
      if [[ "$*" == "resolve --registry-config "*" registry.io/image"*":sha256-"*".src"* ]]
      then
        echo "sha256:9e8f9c7bdce16d2e9ebf93b84d3f8df9821ab74f8c2bf73446e8828f936c9db1"
      else
        echo Mock oras called with: $*
        echo Error: Unexpected call
        exit 1
      fi
  fi
}

function find_signatures() {
  echo $* >> $(workspaces.data.path)/mock_find_signatures.txt

  reference=$(echo $* | grep -oP 'repository \K\w+')
  file=$(echo $* | grep -oP 'output_file (.+)$' | cut -f2 -d' ')
  touch "${file}"

  if [ "${repository}" == "already/signed" ]; then
    echo "registry.redhat.io/already/signed:some-prefix" >> "${file}"
    echo "registry.access.redhat.com/already/signed:some-prefix" >> "${file}"
  fi
}
