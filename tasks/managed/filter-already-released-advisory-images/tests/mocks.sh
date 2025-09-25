#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function get-image-architectures() {
  echo "Mock get-image-architectures called with: $*" >&2
  local image="$1"
  # Produce a single-arch amd64 entry per input image index
  if [[ "$image" == *"sha256:abc123"* ]]; then
    echo '{"platform":{"architecture":"amd64","os":"linux"},"digest":"sha256:amd64digest_abc123"}'
  elif [[ "$image" == *"sha256:def456"* ]]; then
    echo '{"platform":{"architecture":"amd64","os":"linux"},"digest":"sha256:amd64digest_def456"}'
  else
    # Default deterministic output
    echo '{"platform":{"architecture":"amd64","os":"linux"},"digest":"sha256:amd64digest_default"}'
  fi
}

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == *"get internalrequest"*"-o=jsonpath={.status.results}"* ]]
  then
    UNRELEASED=$(echo -n '["new-component", "multi-repo-component", "single-repo-component"]' | gzip -c | base64 -w 0)
    echo '{
      "result": "Success",
      "unreleased_components": "'"$UNRELEASED"'",
      "internalRequestPipelineRunName": "test-pipeline-run",
      "internalRequestTaskRunName": "test-task-run",
      "advisory_url": "https://access.redhat.com/errata/RHBA-2024:1234",
      "advisory_internal_url": "https://gitlab.example.com/repo/-/raw/main/data/advisories/dev/2024/1234/advisory.yaml"
    }'
  else
    /usr/bin/kubectl "$@"
  fi
}
