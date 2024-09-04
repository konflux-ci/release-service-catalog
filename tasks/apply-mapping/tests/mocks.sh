#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts

function date() {
  echo $* >> $(workspaces.config.path)/mock_date.txt

  case "$*" in
      *"+%Y%m%d %T")
          echo "19800101 00:00:00"
          ;;
      *"+%s")
          echo "315550800"
          ;;
      *"+%Y-%m-%d")
          echo "1980-01-01"
          ;;
      *"+%Y-%m")
          echo "1980-01"
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}
