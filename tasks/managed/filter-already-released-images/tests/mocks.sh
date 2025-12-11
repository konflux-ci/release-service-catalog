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
  
  case "$image_ref" in
    # Test: all-released (all tags complete, should be filtered)
    *"@sha256:allrel1")
      echo "sha256:allrel1"
      return 0
      ;;
    *"@sha256:allrel2")
      echo "sha256:allrel2"
      return 0
      ;;
    *"all-released-1:v1")
      echo "sha256:allrel1"
      return 0
      ;;
    *"all-released-2:v2")
      echo "sha256:allrel2"
      return 0
      ;;
    
    # Test: some-released (mixed state)
    *"@sha256:somerel1"|*"@sha256:already1")
      echo "sha256:already1"
      return 0
      ;;
    *"some-released-1:v1")
      echo "sha256:somerel1"
      return 0
      ;;
    *"@sha256:notyet1"|*"not-released:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    *"some-released-2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    # Test: none-released (no tags exist)
    *"@sha256:new1"|*"@sha256:newimg1")
      echo "sha256:new1"
      return 0
      ;;
    *"@sha256:new2"|*"@sha256:newimg2")
      echo "sha256:new2"
      return 0
      ;;
    *"new-image-1:"*|*"new-image-2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    # Test: all-tags-complete
    *"@sha256:alltags1")
      echo "sha256:alltags1"
      return 0
      ;;
    *"all-tags-complete:"*)
      echo "sha256:alltags1"
      return 0
      ;;
    
    # Already released images (tag exists with correct digest)
    *"already-released:latest"|*"already-released:v1.0"|*"already-released:v1.0.5")
      echo "sha256:already1"
      return 0
      ;;
    # Target registry tag checks (when verifying if component is already released)
    "registry.io/already-released:latest"|"registry.io/already-released:v1.0"|"registry.io/already-released:v1.0.5")
      echo "sha256:already1"
      return 0
      ;;
    
    # Not released images (tag not found)
    *"@sha256:notrel1")
      echo "sha256:notrel1"
      return 0
      ;;
    *"not-released:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    # Partial release scenarios (some tags exist, some don't)
    *"@sha256:partial1")
      echo "sha256:partial1"
      return 0
      ;;
    *"partial-released:latest")
      echo "sha256:partial1"
      return 0
      ;;
    *"partial-released:v1.0"|*"partial-released:v1.0.5")
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    # Wrong digest scenarios (tag exists but points to different digest)
    *"@sha256:wrongdigest1"|*"@sha256:correct123")
      echo "sha256:correct123"
      return 0
      ;;
    *"wrong-digest:"*)
      echo "sha256:wrongdigest999"
      return 0
      ;;
    
    # Multi-repo test images
    *"@sha256:inmulti1")
      echo "sha256:inmulti1"
      return 0
      ;;
    *"prod.io/target1:"*)
      echo "sha256:inmulti1"
      return 0
      ;;
    *"@sha256:innone1")
      echo "sha256:innone1"
      return 0
      ;;
    *"@sha256:norepo1")
      echo "sha256:norepo1"
      return 0
      ;;
    *"@sha256:norepo2")
      echo "sha256:norepo2"
      return 0
      ;;
    *"staging.io/target1:"*|*"prod.io/target2:"*|*"staging.io/target2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    # Registry error test (notfound - image not found in registry)
    # Keep pattern narrowly scoped to the dedicated registry.io/image reference
    "registry.io/image:"*|"registry.io/image@sha256:notfound")
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
    
    *)
      # Handle regex patterns that need variable extraction
      if [[ "$image_ref" =~ ^registry\.io/image-([0-9]+)@sha256:(.+)$ ]]; then
        # Large snapshot test source images (always resolve to provided digest)
        local digest="${BASH_REMATCH[2]}"
        echo "sha256:${digest}"
        return 0
      elif [[ "$image_ref" =~ ^reg\.io/target-([0-9]+): ]]; then
        # Large snapshot test target images (only every third component exists)
        local comp_num="${BASH_REMATCH[1]}"
        if [ $((comp_num % 3)) -eq 0 ]; then
          echo "sha256:abcdefg"
          return 0
        else
          echo "Error: manifest unknown: manifest unknown" >&2
          return 1
        fi
      fi
      
      # Default: image not found
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
  esac
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

  case "$image_ref" in
    # Test: all-released (all tags complete, should be filtered)
    *"all-released-1:v1")
      echo '{"Name":"registry.io/all-released-1","Digest":"sha256:allrel1"}'
      return 0
      ;;
    *"all-released-2:v2")
      echo '{"Name":"registry.io/all-released-2","Digest":"sha256:allrel2"}'
      return 0
      ;;

    # Test: some-released (mixed state)
    *"some-released-1:v1")
      echo '{"Name":"registry.io/some-released-1","Digest":"sha256:somerel1"}'
      return 0
      ;;
    *"some-released-2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    # Test: none-released (no tags exist)
    *"new-image-1:"*|*"new-image-2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    # Test: all-tags-complete
    *"all-tags-complete:"*)
      echo '{"Name":"registry.io/all-tags-complete","Digest":"sha256:alltags1"}'
      return 0
      ;;

    # Already released images (tag exists with correct digest)
    *"already-released:latest")
      echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
      return 0
      ;;
    *"already-released:v1.0")
      echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
      return 0
      ;;
    *"already-released:v1.0.5")
      echo '{"Name":"registry.io/already-released","Digest":"sha256:already1"}'
      return 0
      ;;

    # Not released images (tag not found)
    *"not-released:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    # Partial release scenarios (some tags exist, some don't)
    *"partial-released:latest")
      echo '{"Name":"registry.io/partial-released","Digest":"sha256:partial1"}'
      return 0
      ;;
    *"partial-released:v1.0"|*"partial-released:v1.0.5")
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    # Wrong digest scenarios (tag exists but points to different digest)
    *"wrong-digest:"*)
      echo '{"Name":"registry.io/wrong-digest","Digest":"sha256:wrongdigest999"}'
      return 0
      ;;

    # Multi-repo test images
    *"prod.io/target1:"*)
      echo '{"Name":"prod.io/target1","Digest":"sha256:inmulti1"}'
      return 0
      ;;
    *"@sha256:innone1")
      echo '{"Name":"registry.io/image","Digest":"sha256:innone1"}'
      return 0
      ;;
    *"@sha256:norepo1")
      echo '{"Name":"registry.io/image","Digest":"sha256:norepo1"}'
      return 0
      ;;
    *"@sha256:norepo2")
      echo '{"Name":"registry.io/image","Digest":"sha256:norepo2"}'
      return 0
      ;;
    *"staging.io/target1:"*|*"prod.io/target2:"*|*"staging.io/target2:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    # Registry error test (notfound - image not found in registry)
    "registry.io/image:"*)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;

    *)
      # Handle regex patterns that need variable extraction
      if [[ "$image_ref" =~ ^registry\.io/image-([0-9]+)@sha256:(.+)$ ]]; then
        # Large snapshot test source images (always resolve to provided digest)
        local comp_num="${BASH_REMATCH[1]}"
        local digest="${BASH_REMATCH[2]}"
        echo "{\"Name\":\"registry.io/image-$comp_num\",\"Digest\":\"sha256:${digest}\"}"
        return 0
      elif [[ "$image_ref" =~ ^reg\.io/target-([0-9]+): ]]; then
        # Large snapshot test target images (only every third component exists)
        local comp_num="${BASH_REMATCH[1]}"
        if [ $((comp_num % 3)) -eq 0 ]; then
          echo "{\"Name\":\"reg.io/target-$comp_num\",\"Digest\":\"sha256:abcdefg\"}"
          return 0
        else
          echo "Error: manifest unknown: manifest unknown" >&2
          return 1
        fi
      fi

      # Default: image not found (tag doesn't exist)
      echo "Error: manifest unknown: manifest unknown" >&2
      return 1
      ;;
  esac
}
