#!/usr/bin/env bash
set -x

# mocks to be injected into task step scripts

export _python3=$(which python3)
fake_setup=$(mktemp)
cat <<'EOF' > $fake_setup
---
inspect:
  - match:
      image: "docker://quay.io/match-target-digest"
      format: "{{.Digest}}"  # optional
    return: "sha256:match1234567890"  # string when format specified
  - match:
      image: "docker://quay.io/target"
      format: "{{.Digest}}"  # optional
    return: "sha256:target1234567890"  # string when format specified
  - match:
      image: "docker://registry-proxy.engineering.redhat.com/foo"
      format: "{{.Digest}}"  # optional
    return: "sha256:0987654321fedcba"  # string when format specified
  - match:
      image: "docker://registry-proxy.engineering.redhat.com/foo"
      format: "{{.Digest}}"  # optional
    return: "sha256:0987654321fedcba"  # string when format specified
  - match:
      image: "docker://registry-proxy.engineering.redhat.com/fail"
    return:
      error: "skopeo inspect failed"  # string when format specified
      returncode: 1
copy:
  - match:
      source: "docker://registry-proxy.engineering.redhat.com/match@sha256:match1234567890"
      destination: "docker://quay.io/match-target-digest"
    # omit return for success
  - match:
      source: "docker://registry-proxy.engineering.redhat.com/foo@sha256:0987654321fedcba"
      destination: "docker://quay.io/target"
    # omit return for success
  - match:
      source: "docker://quay.io/source@sha256:abcdef1234567890"
      destination: "docker://quay.io/target"
    # omit return for success
  - match:
      source: "docker://registry-proxy.engineering.redhat.com/fail@sha256:0987654321fedcba"
      destination: "docker://quay.io/target"
    return:
      success: false
      error: "skopeo copy failed"  # string when format specified
      returncode: 1
EOF
export RELEASE_SERVICE_UTILS_FAKE_SKOPEO_SETUP=$fake_setup

function python3() {
  "$_python3" -c "
from fake import patch_skopeo_client;
patch_skopeo_client();
from publish_index_image import main;
main();" "${@:3}"
}
