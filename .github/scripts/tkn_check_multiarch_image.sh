#!/usr/bin/env bash
# Fails if any release-service-utils image digest in CHANGED_FILES
# points to a single-arch manifest instead of a multi-arch manifest list.

set -euo pipefail

fail=0

echo "Checking that release-service-utils images are multi-arch manifests"

is_multiarch() {
  ref="$1"

  if ! raw=$(skopeo inspect --raw "docker://${ref}" 2>&1); then
    echo "ERROR: failed to inspect ${ref}"
    echo "  ${raw}"
    grep -rl "${ref}" ${CHANGED_FILES} 2>/dev/null | sed 's/^/  /'
    return 1
  fi

  media_type=$(jq -r '.mediaType // empty' <<< "${raw}")

  # Konflux uses Buildah which produces OCI spec manifests only
  if [[ "${media_type}" == "application/vnd.oci.image.index.v1+json" ]]; then
    echo "OK: ${ref} is multi-arch"
    return 0
  fi

  echo "ERROR: ${ref} must be a multi-arch manifest, got: ${media_type}"
  # show which files reference this digest
  grep -rl "${ref}" ${CHANGED_FILES} 2>/dev/null | sed 's/^/  /'
  return 1
}

# Collect unique image references across all changed YAML files
digests=$(
  for file in ${CHANGED_FILES}; do
    if [[ "${file}" == *.yaml ]]; then
      grep -oP "quay\.io/konflux-ci/release-service-utils@sha256:[a-f0-9]+" "${file}" 2>/dev/null || true
    fi
  done | sort -u
)

if [[ -z "${digests}" ]]; then
  echo "No image references found in changed files"
  exit 0
fi

for ref in ${digests}; do
  if ! is_multiarch "${ref}"; then
    fail=1
  fi
done

exit ${fail}
