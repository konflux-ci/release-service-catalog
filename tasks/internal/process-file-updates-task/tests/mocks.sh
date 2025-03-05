#!/usr/bin/env sh
set -eux

# mocks to be injected into task step scripts
function git() {
  echo "git $*"
  if [[ "$*" == *"clone"* ]]; then
    gitRepo=$(echo "$*" | cut -f5 -d/ | cut -f1 -d.)
    mkdir -p "$gitRepo"
  fi
  if [[ "$*" == "init"* ]]; then
    /usr/bin/git $*
  fi
  if [[ "$*" == "add"* ]]; then
    if [[ "$*" == *"seed-error"* ]]; then
      echo "simulating error"
      exit 1
    else
      /usr/bin/git $*
    fi
  fi
  if [[ "$*" == "status"* ]]; then
    /usr/bin/git $*
  fi
  if [[ "$*" == "commit"* ]]; then
    /usr/bin/git "$@"
  fi
  if [[ "$*" == "config"* ]]; then
    /usr/bin/git "$@"
  fi
  if [[ "$*" == "diff"* ]]; then
    /usr/bin/git "$@"
  fi
}

function glab() {
  if [[ "$*" == *"mr create"* ]]; then
    gitRepo=$(echo "$*" | cut -f5 -d/ | cut -f1 -d.)
    echo "/merge_request/1"
  elif [[ "$*" == *"mr list"* ]]; then
    if [[ "$*" == *"page 1" ]]; then
      echo '!1'
    else
      echo ''
    fi
  elif [[ "$*" == *"mr diff"* ]]; then
    gitRepo=$(echo "$*" | cut -f5 -d/ | cut -f1 -d.)
    if [[ "${gitRepo}" == "replace-idempotent" ]]; then
      echo "
--- addons/my-addon2.yaml
+++ addons/my-addon2.yaml
@@ -1,2 +1,2 @@
-indexImage:
+indexImage: Jack
"
    else
      echo "
+++ test/one-update.yaml
@@ -1,2 +1,2 @@
+indexImage: Jack
"
    fi
  fi
}
