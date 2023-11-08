#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo $* >> $(workspaces.data.path)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request $@ -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function date() {
  echo $* >> $(workspaces.data.path)/mock_date.txt

  case "$*" in
      "+%Y-%m-%dT%H:%M:%SZ")
          echo "2023-10-10T15:00:00Z" |tee $(workspaces.data.path)/mock_date_iso_format.txt
          ;;
      "+%s")
          echo "1696946200" | tee $(workspaces.data.path)/mock_date_epoch.txt
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}
