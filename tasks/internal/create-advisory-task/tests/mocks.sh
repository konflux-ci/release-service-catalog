#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function git() {
  echo "Mock git called with: $*"

  if [[ "$*" == *"clone"* ]]; then
    gitRepo=$(echo "$*" | cut -f5 -d/ | cut -f1 -d.)
    mkdir -p "$gitRepo"/schema
    echo '{"$schema": "http://json-schema.org/draft-07/schema#","type": "object", "properties":{}}' > "$gitRepo"/schema/advisory.json
    mkdir -p "$gitRepo"/data/advisories/dev-tenant
  elif [[ "$*" == *"failing-tenant"* ]]; then
    echo "Mocking failing git command" && false
  else
    # Mock the other git functions to pass
    : # no-op - do nothing
  fi
}

function find() {
  echo "Mock find called with: $*" >&2

  if echo "$*" | grep -q "not-existing-origin"; then
    echo "Error: Unexpected call for not existing origin"
    exit 1
  fi

  if echo "$*" | grep -q "${ADVISORY_BASE_DIR}"; then
    # Simulate directories with timestamps
    echo "1712012345.0 ${ADVISORY_BASE_DIR}/2025/1602"  # Contains image-beta
    echo "1712012344.0 ${ADVISORY_BASE_DIR}/2025/1601"  # Contains image-alpha
    echo "1708012343.0 ${ADVISORY_BASE_DIR}/2024/1452"
    echo "1704012342.0 ${ADVISORY_BASE_DIR}/2024/1442"
  else
    echo "Error: Unexpected find command: $*" >&2
    exit 1
  fi
}

function yq() {
  echo "Mock yq called with: $*" >&2

  if [[ -z "$3" ]]; then
    echo "Error: Empty file path in yq command" >&2
    exit 1
  fi

  advisory_path="$3"
  advisory_year=$(echo "$advisory_path" | awk -F'/' '{print $(NF-2)}')  # Extract Year
  advisory_num=$(echo "$advisory_path" | awk -F'/' '{print $(NF-1)}')   # Extract Advisory Number

  if [[ "$2" == ".spec.type" ]]; then
    echo RHSA
  elif [[ "$2" == ".metadata.name" ]]; then
    echo "${advisory_year}:${advisory_num}"
  else

    echo "Returning advisory content for ${advisory_year}/${advisory_num}" >&2

    case "$advisory_num" in
      1601)
        echo '[{"architecture":"amd64","component":"release-manager-alpha","containerImage":"quay.io/example/release@sha256:alpha123","repository":"example-stream/release","signingKey":"example-sign-key","tags":["v1.0","latest"]}]'
        ;;
      1602)
        echo '[{"architecture":"amd64","component":"release-manager-beta","containerImage":"quay.io/example/release@sha256:beta123","repository":"example-stream/release","signingKey":"example-sign-key","tags":["v2.0","stable"]}]'
        ;;
      1442)
        echo '[{"architecture":"amd64","component":"foo-foo-manager-1-15","containerImage":"quay.io/example/openstack@sha256:abde","repository":"quay.io/example/openstack","signingKey":"example-sign-key","tags":["v1.0","latest"]}]'
        ;;
      1452)
        echo '[{"architecture":"amd64","component":"foo-foo-manager-1-15","containerImage":"quay.io/example/openstack@sha256:lmnop","repository":"quay.io/example/openstack","signingKey":"example-sign-key","tags":["latest"]}]'
        ;;
      *)
        echo "Error: Unexpected advisory number $advisory_num" >&2
        exit 1
        ;;
    esac
  fi
}

function glab() {
  echo "Mock glab called with: $*"

  if [[ "$*" != "auth login"* ]]; then
    echo Error: Unexpected call
    exit 1
  fi
}

function kinit() {
  echo "kinit $*"
}

function curl() {
  echo Mock curl called with: $* >&2

  if [[ "$*" == "--retry 3 --negotiate -u : https://errata/api/v1/advisory/reserve_live_id -XPOST" ]] ; then
    echo '{"live_id": 1234}'
  else
    echo Error: Unexpected call
    exit 1
  fi
}

function date() {
  echo Mock date called with: $* >&2

  case "$*" in
      *"+%Y-%m-%dT%H:%M:%SZ")
          echo "2024-12-12T00:00:00Z"
          ;;
      "*")
          echo Error: Unexpected call
          exit 1
          ;;
  esac
}

function kubectl() {
  # The default SA doesn't have perms to get configmaps, so mock the `kubectl get configmap` call
  if [[ "$*" == "get configmap create-advisory-test-cm -o jsonpath={.data.SIG_KEY_NAME}" ]]
  then
    echo key1
  else
    /usr/bin/kubectl $*
  fi
}
