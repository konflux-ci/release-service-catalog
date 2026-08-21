#!/usr/bin/env bash
set -euo pipefail

# Registry mocks prepended before npm-release-closure-update.
# export -f is required: npm-release-closure-update runs as a bash subprocess.

select-oci-auth() {
  echo "Mock select-oci-auth called with: $*" >&2
  echo '{"auths":{}}'
}

update-npm-closure() {
  echo "Mock update-npm-closure $*" >> "${FILES_DIR}/.closure-call-log"
}

export -f select-oci-auth update-npm-closure
