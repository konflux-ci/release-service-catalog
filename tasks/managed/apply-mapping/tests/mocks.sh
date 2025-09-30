#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts

function date() {
  echo $* >> $(params.dataDir)/mock_date.txt

  case "$*" in
      *"2024-07-29T02:17:29 +%Y-%m-%d")
          echo "2024-07-29"
          ;;
      *"+%Y%m%d %T")
          echo "19800101 00:00:00"
          ;;
      *"+%s")
          echo "315550800"
          ;;
      *"+%Y-%m-%d")
          echo "1980-01-01"
          ;;
      *"+%Y-%m")
          echo "1980-01"
          ;;
      *"+%Y.%m.%d")
          echo "2024.07.29"
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}

function skopeo() {
  echo Mock skopeo called with: $* >&2
  echo $* >> $(params.dataDir)/mock_skopeo.txt

  if [[ "$*" =~ list-tags\ --retry-times\ 3\ docker://repo1 ]]; then
      echo '{"Tags": ["v2.0.0-4", "v2.0.0-3", "v2.0.0-2"]}'
      return
  fi

  if [[ "$*" =~ list-tags\ --retry-times\ 3\ docker://(repoa|repo2) ]]; then
      echo '{"Tags": []}'
      return
  fi

  if [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://registry.io/badimage"* ]]
  then
    echo '{"Labels": {"not-a-build-date": "2024-07-29T02:17:29"}}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://registry.io/labels"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29", "Goodlabel": "labelvalue", "Goodlabel.with-dash": "labelvalue-with-dash", "Badlabel": "label with space"}}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://registry.io/onlycreated"* ]]
  then
    echo '{"Labels": {"not-a-build-date": "2024-07-29T02:17:29"}, "Created": "2024-07-29T02:17:29"}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://quay.io/myorg/web-app"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29"}, "annotations": {"org.opencontainers.image.version": "1.2.3-beta"}}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://quay.io/myorg/api-service"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29"}}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://quay.io/myorg/helm-chart"* ]]
  then
    # Helm chart should fail normal inspect and fall back to raw manifest
    return 1
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --raw docker://quay.io/myorg/helm-chart"* ]]
  then
    echo '{"annotations": {"org.opencontainers.image.version": "2.0.1+alpha", "org.opencontainers.image.created": "2024-07-29T02:17:29Z"}}'
    return
  elif [[ "$*" == "inspect --retry-times 3 --no-tags --override-os linux --override-arch amd64 docker://"* ]]
  then
    echo '{"Labels": {"build-date": "2024-07-29T02:17:29", "org.opencontainers.image.version": "2.0.1+alpha"}}'
    return
  fi

  echo Error: Unexpected call
  exit 1
}

function get-image-architectures() {
    if [[ "$1" == *"helm-chart"* ]]; then
        # Return Helm chart format with configMediaType (only for Helm charts)
        jq -nc '{
            "platform": {"architecture": "amd64", "os": "linux"},
            "digest": "sha256:789abcdef123456",
            "multiarch": false,
            "configMediaType": "application/vnd.cncf.helm.config.v1+json"
        }'
    else
        # Return regular container image format without configMediaType
        jq -nc '{
            "platform": {"architecture": "amd64", "os": "linux"},
            "digest": "abcdefg",
            "multiarch": false
        }'
        jq -nc '{
            "platform": {"architecture": "ppc64le", "os": "linux"},
            "digest": "deadbeef",
            "multiarch": false
        }'
    fi
}
