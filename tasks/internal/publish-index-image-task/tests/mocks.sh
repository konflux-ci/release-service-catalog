#!/usr/bin/env bash
set -x

# mocks to be injected into task step scripts

function skopeo() {
  echo Mock skopeo called with: $* >&2

  if [[ "$1" == "inspect" ]]; then
    # Handle `skopeo inspect`
    if [[ "$*" == *"docker://quay.io/match-target-digest"* ]]; then
      echo "sha256:match1234567890"  # Mock target digest for idempotency check
      return 0
    elif [[ "$*" == *"docker://quay.io/target"* ]]; then
      echo "sha256:target1234567890"
      return 0
    elif [[ "$*" == *"--tls-verify=false --src-creds source docker://quay.io/source"* ]]; then
      echo "sha256:abcdef1234567890"
      return 0
    elif [[ "$*" == *"--tls-verify=false docker://registry-proxy.engineering.redhat.com/foo"* ]]; then
      echo "sha256:0987654321fedcba"
      return 0
    elif [[ "$*" == *"--tls-verify=false docker://registry-proxy.engineering.redhat.com/fail"* ]]; then
      return 1
    else
      echo "Error: Unexpected inspect call"
      exit 1
    fi
  elif [[ "$1" == "copy" ]]; then
    # Handle `skopeo copy`
    if [[ "$*" == *"--src-tls-verify=false --src-creds source docker://quay.io/source"* ]]; then
      return 0
    elif [[ "$*" == *"--src-tls-verify=false docker://registry-proxy.engineering.redhat.com/foo"* ]]; then
      return 0
    elif [[ "$*" == *"--src-tls-verify=false docker://registry-proxy.engineering.redhat.com/fail"* ]]; then
      return 1
    elif [[ "$*" == *"--src-tls-verify=false --src-creds source docker://quay.io/match-source-digest"* ]]; then
      echo "Error: Copy should not be triggered when digests match"
      exit 1
    else
      echo "Error: Unexpected copy call"
      exit 1
    fi
  else
    echo "Error: Unknown skopeo command"
    exit 1
  fi
}
