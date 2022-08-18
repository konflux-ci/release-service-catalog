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
  # Note:
  # 1: catalog dir
  # 2: resource dir
  # 3: name dir
  # 4: version dir
  shift $#
  set -- ${VERSION_DIR////' '}  # Replace all forward-slash with white space
  printf 'Resource: %s\nName: %s\nVersion: %s\n' "$2" "$3" "$4"

  # note: {registry}/{namespace}/{resource-type}-{name}
  printf -v image_string '%s/%s/%s-%s' \
    "$IMAGE_REGISTRY" \
    "$IMAGE_NAMESPACE" \
    "$2" \
    "$3"

  API_HTTP="https://${IMAGE_REGISTRY}/api/v1"

  # Test if the repo does not exist at {registry}/{namespace}.
  if ! grep "${2}-${3}" < <(
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
      "$IMAGE_NAMESPACE" "${2}-${3}" "${2}-${3}" "public" "image"

    printf 'Creating new repo: %s\n' "$image_string"
    curl \
      --silent \
      --request POST "${API_HTTP}/repository?namespace=${IMAGE_NAMESPACE}" \
      --header "Authorization: Bearer ${QUAY_API_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data "$new_repo_string"
  fi

  # Tag with git commit sha hex
  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${GITHUB_SHA:0:7}"
  tkn bundle push -f "${VERSION_DIR}/${3}.yaml" "${image_string}:${GITHUB_SHA:0:7}"

  # Tag with git branch string
  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${GITHUB_REFNAME}"
  tkn bundle push -f "${VERSION_DIR}/${3}.yaml" "${image_string}:${GITHUB_REFNAME}"

  # Tag with version dir string
  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${4}"
  tkn bundle push -f "${VERSION_DIR}/${3}.yaml" "${image_string}:${4}"

done
