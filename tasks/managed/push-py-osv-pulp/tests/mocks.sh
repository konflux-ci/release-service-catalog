#!/usr/bin/env bash
set -eux

# Mock: pulp — for `file content upload`, validate the required flags/env
# and drop the marker file the test checks instead of hitting a real Pulp
# server.
pulp() {
  echo "Mock pulp called: $*"
  : "${PULP_URL:?pulp url not set}"
  : "${PULP_DOMAIN:?pulp domain not set}"
  : "${PULP_FILE_REPOSITORY:?file repo not set}"
  : "${PULP_USERNAME:?pulp username not set}"
  : "${PULP_PASSWORD:?pulp password not set}"
  test -f /etc/service-account-secret/username
  test -f /etc/service-account-secret/password

  local repo=""
  local prev=""
  for a in "$@"; do
    if [ "$prev" = "--repository" ]; then repo="$a"; fi
    prev="$a"
  done
  if [ "$repo" != "${PULP_FILE_REPOSITORY}" ]; then
    echo "ERROR: --repository ($repo) does not match PULP_FILE_REPOSITORY (${PULP_FILE_REPOSITORY})"
    exit 1
  fi

  echo "osv_uploaded" > "${SECURITY_METADATA_DIR}/.osv_upload_marker"
}
export -f pulp
