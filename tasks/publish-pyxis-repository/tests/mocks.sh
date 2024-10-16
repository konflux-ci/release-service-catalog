#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function curl() {
  echo Mock curl called with: $* >&2
  echo $* >> $(workspaces.data.path)/mock_curl.txt

  CALL_ID=$(cat $(workspaces.data.path)/mock_curl.txt | wc -l)

  if [[ "$*" == "--retry 5 --key /tmp/key --cert /tmp/crt https://pyxis.api.redhat.com/v1/repositories/registry/${PYXIS_REGISTRY}/repository/my-product/my-image"?" -X GET" ]]
  then
    # condition for missing Pyxis Repository scenario
    if [[ "$*" == *"my-image9"* ]]; then
      echo '{"detail": "Document in containerRepository not found.", "status": 404, "title": "Not Found", "type": "about:blank", "trace_id": "0x4d7be17d142d24c5f2b10b5f1745cc89"}'
    else
      if [[ "$*" == *"my-image0"* ]]; then
        echo '{"_id": "'$CALL_ID'", "publish_on_push": false, "requires_terms": true}'
      # condition for image not requiring terms
      elif [[ "$*" == *"my-image"[56]* ]]; then
        echo '{"_id": "'$CALL_ID'", "publish_on_push": true, "requires_terms": false}'
      else
        echo '{"_id": "'$CALL_ID'", "publish_on_push": true, "requires_terms": true}'
      fi
    fi
  elif [[ "$*" == '--retry 5 --key /tmp/key --cert /tmp/crt https://pyxis.api.redhat.com/v1/repositories/id/'?' -X PATCH -H Content-Type: application/json --data-binary {"published":true}' ]]
  then
    : # no-op - do nothing
  elif [[ "$*" == '--retry 5 --key /tmp/key --cert /tmp/crt https://pyxis.api.redhat.com/v1/repositories/id/'?' -X PATCH -H Content-Type: application/json --data-binary {"published":true,"source_container_image_enabled":true}' ]]
  then
    : # no-op - do nothing
  else
    echo Error: Unexpected call
    exit 1
  fi
}
