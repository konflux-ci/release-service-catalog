#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function select-oci-auth() {
  # Return empty auth config (all registries are accessible in tests)
  echo '{}'
  return 0
}

function oras() {
  if [[ "$1" != "resolve" ]]; then
    echo "Error: only 'oras resolve' is mocked" >&2
    return 1
  fi
  
  # Extract image reference (last argument)
  local image_ref="${*: -1}"
  
  # Test: all-released (all tags complete, should be filtered)
  if [[ "$image_ref" == *"@sha256:allrel1" ]]; then
    echo "sha256:allrel1"
    return 0
  elif [[ "$image_ref" == *"@sha256:allrel2" ]]; then
    echo "sha256:allrel2"
    return 0
  elif [[ "$image_ref" == *"all-released-1:v1" ]]; then
    echo "sha256:allrel1"
    return 0
  elif [[ "$image_ref" == *"all-released-2:v2" ]]; then
    echo "sha256:allrel2"
    return 0
  
  # Test: some-released (mixed state)
  elif [[ "$image_ref" == *"@sha256:somerel1" ]] || [[ "$image_ref" == *"@sha256:already1" ]]; then
    echo "sha256:already1"
    return 0
  elif [[ "$image_ref" == *"some-released-1:v1" ]]; then
    echo "sha256:somerel1"
    return 0
  elif [[ "$image_ref" == *"@sha256:notyet1" ]] || [[ "$image_ref" == *"not-released:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  elif [[ "$image_ref" == *"some-released-2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Test: none-released (no tags exist)
  elif [[ "$image_ref" == *"@sha256:new1" ]] || [[ "$image_ref" == *"@sha256:newimg1" ]]; then
    echo "sha256:new1"
    return 0
  elif [[ "$image_ref" == *"@sha256:new2" ]] || [[ "$image_ref" == *"@sha256:newimg2" ]]; then
    echo "sha256:new2"
    return 0
  elif [[ "$image_ref" == *"new-image-1:"* ]] || [[ "$image_ref" == *"new-image-2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Test: all-tags-complete
  elif [[ "$image_ref" == *"@sha256:alltags1" ]]; then
    echo "sha256:alltags1"
    return 0
  elif [[ "$image_ref" == *"all-tags-complete:"* ]]; then
    echo "sha256:alltags1"
    return 0
  
  # Already released images (tag exists with correct digest)
  elif [[ "$image_ref" == *"@sha256:already1" ]]; then
    echo "sha256:already1"
    return 0
  elif [[ "$image_ref" == *"already-released:latest" ]] || [[ "$image_ref" == *"already-released:v1.0" ]] || [[ "$image_ref" == *"already-released:v1.0.5" ]]; then
    echo "sha256:already1"
    return 0
  # Target registry tag checks (when verifying if component is already released)
  elif [[ "$image_ref" == "registry.io/already-released:latest" ]] || [[ "$image_ref" == "registry.io/already-released:v1.0" ]] || [[ "$image_ref" == "registry.io/already-released:v1.0.5" ]]; then
    echo "sha256:already1"
    return 0
  
  # Not released images (tag not found)
  elif [[ "$image_ref" == *"@sha256:notrel1" ]]; then
    echo "sha256:notrel1"
    return 0
  elif [[ "$image_ref" == *"not-released:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Partial release scenarios (some tags exist, some don't)
  elif [[ "$image_ref" == *"@sha256:partial1" ]]; then
    echo "sha256:partial1"
    return 0
  elif [[ "$image_ref" == *"partial-released:latest" ]]; then
    echo "sha256:partial1"
    return 0
  elif [[ "$image_ref" == *"partial-released:v1.0" ]] || [[ "$image_ref" == *"partial-released:v1.0.5" ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Wrong digest scenarios (tag exists but points to different digest)
  elif [[ "$image_ref" == *"@sha256:wrongdigest1" ]] || [[ "$image_ref" == *"@sha256:correct123" ]]; then
    echo "sha256:correct123"
    return 0
  elif [[ "$image_ref" == *"wrong-digest:"* ]]; then
    echo "sha256:wrongdigest999"
    return 0
  
  # Multi-repo test images
  elif [[ "$image_ref" == *"@sha256:inmulti1" ]]; then
    echo "sha256:inmulti1"
    return 0
  elif [[ "$image_ref" == *"prod.io/target1:"* ]]; then
    echo "sha256:inmulti1"
    return 0
  elif [[ "$image_ref" == *"@sha256:innone1" ]]; then
    echo "sha256:innone1"
    return 0
  elif [[ "$image_ref" == *"@sha256:norepo1" ]]; then
    echo "sha256:norepo1"
    return 0
  elif [[ "$image_ref" == *"@sha256:norepo2" ]]; then
    echo "sha256:norepo2"
    return 0
  elif [[ "$image_ref" == *"staging.io/target1:"* ]] || [[ "$image_ref" == *"prod.io/target2:"* ]] || [[ "$image_ref" == *"staging.io/target2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Registry error test (notfound - image not found in registry). Keep pattern narrowly scoped
  # to the dedicated registry.io/image reference used by the error test so large snapshot data
  # (registry.io/image-<n>@sha256:notfound) can fall through to their own handlers.
  elif [[ "$image_ref" == "registry.io/image:"* ]] || [[ "$image_ref" == "registry.io/image@sha256:notfound" ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1
  
  # Secure registry test (autherror - should trigger real error)
  elif [[ "$image_ref" == *"registry.io/secure:"* ]] || [[ "$image_ref" == *"@sha256:autherror" ]] || [[ "$image_ref" == *":autherror" ]]; then
    echo "Error: unauthorized: authentication required" >&2
    return 1
  
  # Large snapshot test source images (always resolve to provided digest)
  elif [[ "$image_ref" =~ ^registry\.io/image-([0-9]+)@sha256:(.+)$ ]]; then
    local digest="${BASH_REMATCH[2]}"
    echo "sha256:${digest}"
    return 0

  # Large snapshot test target images (only every third component exists)
  elif [[ "$image_ref" =~ ^reg\.io/target-([0-9]+): ]]; then
    local comp_num="${BASH_REMATCH[1]}"
    if [ $((comp_num % 3)) -eq 0 ]; then
      echo "sha256:abcdefg"
      return 0
    else
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
    fi
  
  # Error scenarios for testing error handling
  elif [[ "$image_ref" == *"@sha256:realerror" ]] || [[ "$image_ref" == *":realerror" ]]; then
    echo "Error: connection refused: unable to connect to registry" >&2
    return 1
  elif [[ "$image_ref" == *"@sha256:networkerror" ]] || [[ "$image_ref" == *":networkerror" ]]; then
    echo "Error: dial tcp: lookup registry.example.com: no such host" >&2
    return 1
  fi
  
  # Default: image not found
  echo "Error: manifest unknown: manifest unknown" >&2
  return 1
}

function skopeo() {
  # Extract image reference (expects tag format: docker://registry:tag)
  local image_ref=""
  for arg in "$@"; do
    if [[ "$arg" == docker://* ]]; then
      image_ref="${arg#docker://}"
      break
    fi
  done

  # Test: all-released (all tags complete, should be filtered)
  if [[ "$image_ref" == *"all-released-1:v1" ]]; then
    echo '{"Name":"registry.io/all-released-1","Digest":"sha256:allrel1"}'
    return 0
  elif [[ "$image_ref" == *"all-released-2:v2" ]]; then
    echo '{"Name":"registry.io/all-released-2","Digest":"sha256:allrel2"}'
    return 0

  # Test: some-released (mixed state)
  elif [[ "$image_ref" == *"some-released-1:v1" ]]; then
    echo '{"Name":"registry.io/some-released-1","Digest":"sha256:somerel1"}'
    return 0
  elif [[ "$image_ref" == *"some-released-2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Test: none-released (no tags exist)
  elif [[ "$image_ref" == *"new-image-1:"* ]] || [[ "$image_ref" == *"new-image-2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Test: all-tags-complete
  elif [[ "$image_ref" == *"all-tags-complete:"* ]]; then
    echo '{"Name":"registry.io/all-tags-complete","Digest":"sha256:alltags1"}'
    return 0

  # Already released images (tag exists with correct digest)
  elif [[ "$image_ref" == *"already-released:latest" ]]; then
    echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
    return 0
  elif [[ "$image_ref" == *"already-released:v1.0" ]]; then
    echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
    return 0
  elif [[ "$image_ref" == *"already-released:v1.0.5" ]]; then
    echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
    return 0

  # Not released images (tag not found)
  elif [[ "$image_ref" == *"not-released:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Partial release scenarios (some tags exist, some don't)
  elif [[ "$image_ref" == *"partial-released:latest" ]]; then
    echo '{"Name":"registry.io/partial-released","Digest":"sha256:partial1"}'
    return 0
  elif [[ "$image_ref" == *"partial-released:v1.0" ]] || [[ "$image_ref" == *"partial-released:v1.0.5" ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Wrong digest scenarios (tag exists but points to different digest)
  elif [[ "$image_ref" == *"wrong-digest:"* ]]; then
    echo '{"Name":"registry.io/wrong-digest","Digest":"sha256:wrongdigest999"}'
    return 0

  # Multi-repo test images
  elif [[ "$image_ref" == *"prod.io/target1:"* ]]; then
    echo '{"Name":"prod.io/target1","Digest":"sha256:inmulti1"}'
    return 0
  elif [[ "$image_ref" == *"@sha256:innone1" ]]; then
    echo '{"Name":"registry.io/image","Digest":"sha256:innone1"}'
    return 0
  elif [[ "$image_ref" == *"@sha256:norepo1" ]]; then
    echo '{"Name":"registry.io/image","Digest":"sha256:norepo1"}'
    return 0
  elif [[ "$image_ref" == *"@sha256:norepo2" ]]; then
    echo '{"Name":"registry.io/image","Digest":"sha256:norepo2"}'
    return 0
  elif [[ "$image_ref" == *"staging.io/target1:"* ]] || [[ "$image_ref" == *"prod.io/target2:"* ]] || [[ "$image_ref" == *"staging.io/target2:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Registry error test (notfound - image not found in registry)
  elif [[ "$image_ref" == "registry.io/image:"* ]]; then
    echo "Error: manifest unknown: manifest unknown" >&2
    return 1

  # Secure registry test (autherror - should trigger real error)
  elif [[ "$image_ref" == *"registry.io/secure:"* ]]; then
    echo "Error: unauthorized: authentication required" >&2
    return 1

  # Large snapshot test source images (always resolve to provided digest)
  elif [[ "$image_ref" =~ ^registry\.io/image-([0-9]+)@sha256:(.+)$ ]]; then
    local comp_num="${BASH_REMATCH[1]}"
    local digest="${BASH_REMATCH[2]}"
    echo "{\"Name\":\"registry.io/image-$comp_num\",\"Digest\":\"sha256:${digest}\"}"
    return 0

  # Large snapshot test target images (only every third component exists)
  elif [[ "$image_ref" =~ ^reg\.io/target-([0-9]+): ]]; then
    local comp_num="${BASH_REMATCH[1]}"
    if [ $((comp_num % 3)) -eq 0 ]; then
      echo "{\"Name\":\"reg.io/target-$comp_num\",\"Digest\":\"sha256:abcdefg\"}"
      return 0
    else
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
    fi

  # Error scenarios for testing error handling
  elif [[ "$image_ref" == *"@sha256:autherror" ]] || [[ "$image_ref" == *":autherror" ]]; then
    echo "Error: unauthorized: authentication required" >&2
    return 1
  elif [[ "$image_ref" == *"@sha256:realerror" ]] || [[ "$image_ref" == *":realerror" ]]; then
    echo "Error: connection refused: unable to connect to registry" >&2
    return 1
  elif [[ "$image_ref" == *"@sha256:networkerror" ]] || [[ "$image_ref" == *":networkerror" ]]; then
    echo "Error: dial tcp: lookup registry.example.com: no such host" >&2
    return 1
  fi

  # Default: image not found (tag doesn't exist)
  echo "Error: manifest unknown: manifest unknown" >&2
  return 1
}
