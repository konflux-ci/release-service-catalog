# mocks to be injected into task step scripts

#!/bin/sh -ex

function skopeo() {
  echo "Mock skopeo called with: $*" >&2
  
  # Append call information to mock_skopeo.txt
  echo "$*" >> $(workspaces.data.path)/mock_skopeo.txt

 
  if [[ "$*" == "inspect --raw docker://quay.io/hacbs-release-tests/test-ocp-version/test-fbc-component@sha256:f6e744662e342c1321deddb92469b55197002717a15f8c0b1bb2d9440aac2297" ]]; then
    echo '{"annotations":{"org.opencontainers.image.base.name":"registry.redhat.io/openshift4/ose-operator-registry:v4.12"}}'
    return
  fi

  # If the command is not the expected inspect --raw, output an error and exit
  echo Error: Unexpected call of skopeo
  exit 1
}
