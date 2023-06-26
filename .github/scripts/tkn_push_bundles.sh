#!/bin/bash

printf 'Gathering new/modified bundle definitions.\n'

# Gather new/modified bundle definitions.
declare -A bundle_versioned_dirs  # associative array to hash bundle dirs in key space.
for file in ${ALL_CHANGED_FILES}
do
  printf 'MATCHED: %s\n' "$file"
  bundle_versioned_dirs["${file%/*}"]=""  # hash the bundle version dir
done
# EO gathering changed definitions
printf 'bundle_versioned_dirs: %s\n' "${!bundle_versioned_dirs[@]}"

# Main loop
printf 'Pushing any new/modified bundle definitions.\n'
for VERSION_DIR in "${!bundle_versioned_dirs[@]}"
do
  if [[ ! -d "$VERSION_DIR" ]]
  then
    printf 'Skipping non-existing bundle-path: %s\n' "$VERSION_DIR"
    continue
  fi
  shift $#
  set -- ${VERSION_DIR////' '}  # Replace all forward-slash with white space
  # 1: catalog dir, but not needed so not set
  resource=$2
  name=$3
  version=$4
  # Reassign variables if VERSION_DIR is part of upstream tasks
  if [[ "${name}" == "upstream" ]]
  then
    name="$5"
    version="$6"
  fi
  printf 'Resource: %s\nName: %s\nVersion: %s\n' "$resource" "$name" "$version"

  # note: {registry}/{namespace}/{resource-type}-{name}
  printf -v image_string '%s/%s/%s-%s' \
    "$IMAGE_REGISTRY" \
    "$IMAGE_NAMESPACE" \
    "$resource" \
    "$name"

  API_HTTP="https://${IMAGE_REGISTRY}/api/v1"
  VERSION=$(echo ${VERSION_DIR} | grep -o '[^/]*$')
  LATEST_VERSION=$(ls ${VERSION_DIR}/.. --hide=OWNERS | sort -V | tail -n 1)

  # Test if the repo does not exist at {registry}/{namespace}.
  if ! grep "${resource}-${name}" < <(
    curl \
      --silent \
      --request GET "${API_HTTP}/repository?namespace=${IMAGE_NAMESPACE}" \
      --header "Authorization: Bearer ${QUAY_API_TOKEN}" | \
    jq '.repositories[].name'
  )
  then
    # Repo does not exist, so first create the repo.
    printf -v new_repo_string -- \
      '{"namespace": "%s", "repository": "%s", "description": "%s", "visibility": "%s", "repo_kind": "%s"}' \
      "$IMAGE_NAMESPACE" "${resource}-${name}" "${resource}-${name}" "public" "image"

    printf 'Creating new repo: %s\n' "$image_string"
    curl \
      --silent \
      --request POST "${API_HTTP}/repository?namespace=${IMAGE_NAMESPACE}" \
      --header "Authorization: Bearer ${QUAY_API_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data "$new_repo_string"
  fi

  # Tag with version dir string
  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${version}"
  tkn bundle push -f "${VERSION_DIR}/${name}.yaml" "${image_string}:${version}"

  # Tag with catalog version + git commit sha hex
  # {catalog_version}-{commit_sha1}
  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${version}-${GITHUB_SHA:0:7}"
  tkn bundle push -f "${VERSION_DIR}/${name}.yaml" "${image_string}:${version}-${GITHUB_SHA:0:7}"

  # Tag with main if this is the latest version
  if [ "${LATEST_VERSION}" == "${VERSION}" ]
  then
    printf 'Pushing image to repo: %s:%s\n' "$image_string" "main"
    tkn bundle push -f "${VERSION_DIR}/${name}.yaml" "${image_string}:main"
  else
    printf 'Did not push %s:%s to main as current latest version found to be %s\n' \
      "${image_string}" "${VERSION}" "${LATEST_VERSION}"
  fi
done
