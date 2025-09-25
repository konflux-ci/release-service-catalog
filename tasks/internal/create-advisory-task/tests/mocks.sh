#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function git() {
  echo "Mock git called with: $*"

  if [[ "$1" == "clone" ]]; then
    gitRepo=$(echo "$*" | cut -f5 -d/ | cut -f1 -d.)
    mkdir -p "$gitRepo"/schema
    echo '{"$schema": "http://json-schema.org/draft-07/schema#","type": "object", "properties":{}}' > "$gitRepo"/schema/advisory.json

    mkdir -p "$gitRepo"/data/advisories/dev-tenant/2025/1602
    mkdir -p "$gitRepo"/data/advisories/dev-tenant/2025/1601
    mkdir -p "$gitRepo"/data/advisories/dev-tenant/2024/1452
    mkdir -p "$gitRepo"/data/advisories/dev-tenant/2024/1442

    touch -d "@1712012345" "$gitRepo"/data/advisories/dev-tenant/2025/1602
    touch -d "@1712012344" "$gitRepo"/data/advisories/dev-tenant/2025/1601
    touch -d "@1708012343" "$gitRepo"/data/advisories/dev-tenant/2024/1452
    touch -d "@1704012342" "$gitRepo"/data/advisories/dev-tenant/2024/1442
  elif [[ "$1" == "sparse-checkout" ]]; then
    : # no-op
  elif [[ "$1" == "ls-tree" ]]; then
    echo data/advisories/dev-tenant/2025/1602/advisory.yaml
    echo data/advisories/dev-tenant/2025/1601/advisory.yaml
    echo data/advisories/dev-tenant/2024/1452/advisory.yaml
    echo data/advisories/dev-tenant/2024/1442/advisory.yaml
  elif [[ "$*" == *"failing-tenant"* ]]; then
    echo "Mocking failing git command" && false
  else
    # Mock the other git functions to pass
    : # no-op - do nothing
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

function check-jsonschema() {
  echo "Mock check-jsonschema called with: $*"

  if [[ "$*" == *"schema-tenant"* ]]; then
    # Use a bogus file so it fails validation
    echo "A:B:C" > /tmp/fail.yaml
    /usr/local/bin/check-jsonschema "$1" "$2" /tmp/fail.yaml
  else
    /usr/local/bin/check-jsonschema $*
  fi
}

# The retry script won't see the kinit function unless we export it
export -f kinit
