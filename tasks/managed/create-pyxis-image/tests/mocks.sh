#!/usr/bin/env bash
set -exo pipefail

# mocks to be injected into task step scripts

function create_container_image() {
  echo $* >> $(params.dataDir)/mock_create_container_image.txt

  # Extract repository name from parameters to determine the line number
  # This allows us to have a thread-safe way to determine the image id without locking
  local repository=""
  local args=("$@")

  # Parse arguments to extract the --name parameter (repository)
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[i]}" == "--name" && $((i+1)) -lt ${#args[@]} ]]; then
      repository="${args[i+1]}"
      break
    fi
  done

  # Find the line number where this repository appears in the file
  local matching_lines=$(grep -n -- "--name $repository" "$(params.dataDir)/mock_create_container_image.txt")
  local line_count=$(echo "$matching_lines" | wc -l)

  # Use the last line number for this repository (handles multi-arch images)
  # WARNING: this is thread safe as long as the repository name is unique. If you need to
  # test thread safety, you need to use a different repository name for each request.
  if [[ "$line_count" -gt 0 ]]; then
    local line_number=$(echo "$matching_lines" | tail -1 | cut -d: -f1)
    printf "The image id is %04d\n" "$line_number"
  else
    # Fallback: count total lines in file (original behavior)
    local total_lines=$(wc -l < "$(params.dataDir)/mock_create_container_image.txt" 2>/dev/null || echo "0")
    local image_id=$((total_lines + 1))
    printf "The image id is %04d\n" "$image_id"
  fi

  if [[ "$*" != "--pyxis-url https://pyxis.preprod.api.redhat.com/ --certified false --tags "*" --is-latest false --verbose --oras-manifest-fetch "*" --name "*" --media-type "*" --digest "*" --architecture-digest "*" --architecture "*" --rh-push "* ]]
  then
    echo Error: Unexpected call
    echo Mock create_container_image called with: $*
    exit 1
  fi
}

function cleanup_tags() {
  echo $* >> $(params.dataDir)/mock_cleanup_tags.txt

  if [[ "$*" != "--verbose --retry --pyxis-graphql-api https://graphql-pyxis.preprod.api.redhat.com/graphql/ --repository "*" "00?? ]]
  then
    echo Error: Unexpected call
    echo Mock cleanup_tags called with: $*
    exit 1
  fi
}

function skopeo() {
  echo $* >> $(params.dataDir)/mock_skopeo.txt
  if [[ "$*" == "inspect --retry-times 3 --raw docker://registry.io/oci-artifact"* ]]
  then
    echo '{"mediaType": "application/vnd.oci.image.index.v1+json"}'
  elif [[ "$*" == "inspect --retry-times 3 --raw docker://"* ]] || [[ "$*" == "inspect --no-tags --override-os linux --override-arch "*" docker://"* ]]
  then
    echo '{"mediaType": "my_media_type+gzip"}'
  else
    echo Mock skopeo called with: $*
    if [[ "$*" != "inspect --no-tags docker://"* ]]
    then
      echo Error: Unexpected call
      exit 1
    fi
  fi
}

function get-image-architectures() {
  if [[ "$*" =~ registry.io/multi-arch-image.?@sha256:mydigest.? ]]; then
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
    echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
  elif [[ "$1" = registry.io/fail-get-image-architectures@sha256:mydigest ]]; then
    echo "Simulating get-image-architectures failure" >&2
    return 1
  elif [[ "$1" == *"registry.io/oci-artifact@sha256:mydigest"* ]]; then
    # This represents the OCI artifact test case - will include configMediaType
    jq -nc '{
      "platform": {"architecture": "amd64", "os": "linux"},
      "digest": "abcdefg",
      "configMediaType": "application/vnd.oci.artifact.config.v1+json"
    }'
  elif [[ "$1" == *"helm-chart"* ]]; then
    # This represents Helm charts - will include Helm configMediaType
    jq -nc '{
      "platform": {"architecture": "amd64", "os": "linux"},
      "digest": "abcdefg",
      "multiarch": false,
      "configMediaType": "application/vnd.cncf.helm.config.v1+json"
    }'
  else
    # Regular container images - no configMediaType in output
    echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
  fi
}

function select-oci-auth() {
  echo $* >> $(params.dataDir)/mock_select-oci-auth.txt
}

function oras() {
  echo $* >> $(params.dataDir)/mock_oras.txt
  if [[ "$*" == "blob fetch --registry-config"*"/tmp/oras-blob-fetch"*"-beef.gz"* ]]
  then
    index=$(echo "$*" | grep -oP 'oras-blob-fetch-\K\d+(?=-beef\.gz)')
    echo -n 'H4sIAAAAAAAAA0vKzEssqlRISSxJVEjPTy1WyEgtSgUAXVhZVxUAAAA=' | base64 -d > /tmp/oras-blob-fetch-${index}-beef.gz
  elif [[ "$*" == "blob fetch --registry-config"*"/tmp/oras-blob-fetch"*"-pork.gz"* ]]
  then
    index=$(echo "$*" | grep -oP 'oras-blob-fetch-\K\d+(?=-pork\.gz)')
    echo -n 'H4sIAAAAAAAAA8vNL0pVSEksSQQA2pxWLAkAAAA=' | base64 -d > /tmp/oras-blob-fetch-${index}-pork.gz
  elif [[ "$*" == "manifest fetch --registry-config"*image-with-gzipped-layers* ]]
  then
    echo '{"mediaType": "my_media_type", "layers": [{"mediaType": "blob+gzip", "digest": "beef"}, {"mediaType": "blob+gzip", "digest": "pork"}]}'
  elif [[ "$*" == "manifest fetch --registry-config"* ]]
  then
    echo '{"mediaType": "my_media_type", "layers": [{"mediaType": "blob+other", "digest": "tofu"}]}'
  elif [[ "$*" == "pull --registry-config"*dockerfile-not-found:sha256-*.dockerfile* ]]
  then
    echo Mock oras called with: $*
    return 1
  elif [[ "$*" == "pull --registry-config"*dockerfile-file-missing:sha256-*.dockerfile* ]]
  then
    echo Mock oras called with: $*
  elif [[ "$*" == "pull --registry-config"*":sha256-"*.dockerfile* ]]
  then
    echo Mock oras called with: $*
    echo mydocker > $6/Dockerfile
  else
    echo Mock oras called with: $*
    echo Error: Unexpected call
    exit 1
  fi
}
