#!/bin/bash

printf 'Gathering new/modified bundle definitions.\n'

# Gather new/modified bundle definitions.
declare -A bundle_dirs  # associative array to hash bundle dirs in key space.
while read file
do
  # Only match yaml files in bundle dirs within definitions dir.
  if [[ $file =~ .*[-,_]{2,} ]]
  then
    printf 'NO consecutive hyphen or underscores allowed: %s\n' "$file"
  elif [[ ${file} =~ ^("./")?"definitions/"[a-z,A-Z,0-9,_-]+"/"[a-z,A-Z,0-9,_-]+".yaml"$ ]]
  then
    printf 'MATCHED: %s\n' "$file"
    bundle_dirs["${file%/*}"]=""  # hash the bundle dir
  else
    printf 'NO MATCH: %s\n' "$file"
  fi
done < <(git diff-tree --no-commit-id --name-only -r ${GITHUB_SHA})
# EO gathering changed definitions
printf 'bundle_dirs: %s\n' "${!bundle_dirs[@]}"

# Main loop
printf 'Pushing any new/modified bundle definitions.\n'
for BUNDLE_DIR in "${!bundle_dirs[@]}"
do
  if [[ ! -d "$BUNDLE_DIR" ]]
  then
    printf 'Skipping non-existing bundle-path: %s\n' "$BUNDLE_DIR"
    continue
  fi
  BUNDLE_FILES=()
  BUNDLE_NAME=${BUNDLE_DIR##*/}
  printf '* Bundle_dir: %s\n' $BUNDLE_DIR
  printf '* Bundle name: %s\n' $BUNDLE_NAME
  for file in $BUNDLE_DIR/*.yaml
  do
    [[ -e "$file" ]] || continue
    printf '  * file: %s\n' "$file"
    BUNDLE_FILES+=("$file")
  done

  # xxx - tkn cli is apparently unable to process a list of bundle files on one `-f` cmdline arg.
  # So we have to process `-f` for each definition file 1:1.
  # (fix upstream)
  printf -v bundle_files_args -- '-f %s ' ${BUNDLE_FILES[*]}
  unset BUNDLE_FILES

  # note: {registry}/{namespace}/{repository}
  printf -v image_string '%s/%s/%s' \
    ${IMAGE_REGISTRY} \
    ${IMAGE_NAMESPACE} \
    "${BUNDLE_NAME}"

    API_HTTP="https://${IMAGE_REGISTRY}/api/v1"

  # Test if the repo does not exist at {registry}/{namespace}.
  if ! grep "${BUNDLE_NAME}" < <(
    curl \
      --silent \
      --request GET "${API_HTTP}/repository?namespace=${IMAGE_NAMESPACE}" \
      --header 'Authorization: Bearer ${QUAY_API_TOKEN}' | \
    jq '.repositories[].name'
  )
  then
    # Repo does not exist, so first create the repo.
    printf -v new_repo_string -- \
      '{"namespace": "%s", "repository": "%s", "description": "%s", "visibility": "%s", "repo_kind": "%s"}' \
      "${IMAGE_NAMESPACE}" "${BUNDLE_NAME}" "${BUNDLE_NAME}" "public" "image"

    printf 'Creating new repo: %s\n' "$image_string"
    curl \
      --silent \
      --request POST "${API_HTTP}/repository?namespace=${IMAGE_NAMESPACE}" \
      --header 'Authorization: Bearer ${QUAY_API_TOKEN}' \
      --header 'Content-Type: application/json' \
      --data "$new_repo_string"
  fi

  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${GITHUB_SHA:0:7}"
  tkn bundle push ${bundle_files_args} "${image_string}:${GITHUB_SHA:0:7}"

  printf 'Pushing image to repo: %s:%s\n' "$image_string" "${GITHUB_REFNAME}"
  tkn bundle push ${bundle_files_args} "${image_string}:${GITHUB_REFNAME}"

done
