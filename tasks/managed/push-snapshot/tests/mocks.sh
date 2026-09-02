#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function cosign() {
  echo Mock cosign called with: $*
  echo $* >> "$(params.dataDir)/mock_cosign.txt"

  # Handle both old format and new format with --only flag for parallel test
  if [[ "$*" == copy\ -f\ registry.io/parallel-image:tag* ]] || \
     [[ "$*" == copy\ -f\ --only=*\ registry.io/parallel-image:tag* ]]
  then
    LOCK_FILE="$(params.dataDir)/${RANDOM}.lock"
    touch $LOCK_FILE
    sleep 2
    LOCK_FILE_COUNT="$(ls "$(params.dataDir)/"*.lock | wc -l)"
    # Create a .count file to log the number of parallel cosign calls currently running.
    echo $LOCK_FILE_COUNT > "$(params.dataDir)/${RANDOM}.count"
    sleep 2
    rm $LOCK_FILE
  fi

  # mock cosign failing for the no-permission test
  # Handle both old format (copy -f) and new format (copy -f --only=...)
  if [[ "$*" == copy\ -f\ registry.io/no-permmission:tag* ]] || \
     [[ "$*" == copy\ -f\ --only=*\ registry.io/no-permmission:tag* ]]
  then
    echo Invalid credentials for registry.io/no-permmission:tag
    return 1
  fi

  # mock cosign failing the first 3x for the retry test
  if [[ "$*" == copy\ -f\ registry.io/retry-image:tag* ]] || \
     [[ "$*" == copy\ -f\ --only=*\ registry.io/retry-image:tag* ]]
  then
    if [[ "$(wc -l < "$(params.dataDir)/mock_cosign.txt")" -le 3 ]]
    then
      echo Expected cosign call failure for retry test
      return 1
    fi
  fi

  # Handle both old format and new format with --only flag for private-registry test
  if [[ "$*" == copy\ -f\ private-registry.io/image:tag* ]] || \
     [[ "$*" == copy\ -f\ --only=*\ private-registry.io/image:tag* ]]
  then
    # Verify CA certificate file exists and contains valid PEM data
    if [[ ! -f /etc/pki/tls/certs/ca-bundle.crt ]]
    then
      echo Custom certificate not mounted
      return 1
    fi
    if ! grep -q "BEGIN CERTIFICATE" /etc/pki/tls/certs/ca-bundle.crt
    then
      echo Custom certificate is not in valid PEM format
      return 1
    fi
  fi

  # Accept both old format (copy -f src dst) and new format with --only flag
  if [[ "$*" != copy\ -f\ *:*\ *:* ]] && \
     [[ "$*" != copy\ -f\ --only=* ]]
  then
    echo Error: Unexpected call
    exit 1
  fi
}

function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> "$(params.dataDir)/mock_skopeo.txt"
  if [[ "$*" == "inspect --retry-times 3 --raw docker://reg.io/test@sha256:abcdefg" ]]; then
    echo '{"mediaType": "application/vnd.oci.image.index.v1+json", "manifests": [{"platform":{"os":"linux","architecture":"amd64"}}, {"platform":{"os":"linux","architecture":"ppc64le"}}]}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --raw docker://"* ]]; then
    echo '{"mediaType": "my_media_type"}'
    return
  elif [[ "$*" == copy\ -a\ --src-authfile\ *\ --dest-authfile\ *\ docker://*\ docker://* ]]; then
    # Handle skopeo copy for image data
    return 0
  fi

  # If neither of the above matched, it's an unexpected call
  echo Error: Unexpected call
  exit 1
}

function get-image-architectures() {
  echo '{"platform":{"architecture": "ppc64le", "os": "linux"}, "digest": "deadbeef"}'
  echo '{"platform":{"architecture": "amd64", "os": "linux"}, "digest": "abcdefg"}'
}

function select-oci-auth() {
  echo $* >> "$(params.dataDir)/mock_select-oci-auth.txt"
}

function oras() {
  echo $* >> "$(params.dataDir)/mock_oras.txt"
  if [[ "$1" == "discover" ]]; then
    # Match the reference within the full argument string (last arg may be --format json)
    if [[ " $* " == *" reg.io/test@sha256:abcdefg "* ]]; then
      # Simulate one attached artifact for this image
      echo '{"referrers": [{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:deadbeef","size":123}]}'
    else
      echo '{"referrers": []}'
    fi
    return 0
  fi
  # Accept oras cp -r calls (used to copy image and its attached artifacts)
  if [[ "$1" == "cp" ]]; then
    if [[ "$2" == "-r" ]]; then
      # Old format: oras cp -r source dest
      return 0
    elif [[ "$2" == "--from-registry-config" ]]; then
      # New format: oras cp --from-registry-config ... --to-registry-config ... [--platform ...] source dest
      # This handles both migration artifact copying and regular cp with --platform
      return 0
    fi
  fi
  if [[ "$*" == "resolve --registry-config "*" "* ]]; then
    if [[ "$*" =~ "--platform" && "$4" =~ ".src" ]]; then
      echo "Error: .src images should not use --platform" >&2
      exit 1
    fi
    if [[ "$4" == "reg.io/test@sha256:abcdefg" ]]; then
      echo "sha256:abcdefg"
    elif [[ "$4" == "registry.io/image1:tag1" ]]; then
      echo "sha256:6ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15e"
    elif [[ "$4" == "registry.io/image2:tag2" ]]; then
      echo "sha256:7ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15f"
    elif [[ "$4" == "registry.io/image1:sha256-6ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15e.src" ]]; then
      echo "sha256:6ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15e"
    elif [[ "$4" == "registry.io/image2:sha256-7ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15f.src" ]]; then
      echo "sha256:7ff029b0b6cf82e3df2a2360dc88cd527c51132b557207d64634d9c245e0d15f"
    elif [[ "$4" == "reg.io/test:sha256-abcdefg.src" ]]; then
      echo "sha256:abcdefg"
    elif [[ "$4" == "prod.io/loc:sha256-abcdefg.src" ]]; then
      echo "sha256:abcdefg"
    elif [[ "$4" == "prod.io/loc:multi-tag-source" ]]; then
      echo "sha256:abcdefg"
    elif [[ "$4" == *skip-image*.src || "$4" == *skip-image*-source ]]; then
      echo "sha256:000000"
    elif [[ "$4" == *skip-image* ]]; then
      echo "sha256:111111"
    else
      # echo the shasum computed from the pull spec so the task knows if two images are the same
      echo -n "sha256:"
      echo $4 | sha256sum | cut -d ' ' -f 1
    fi
    return
  else
    echo Mock oras called with: $*
    echo Error: Unexpected call
    exit 1
  fi
}
