#!/usr/bin/env bash
set -ex

CONTENT_EXISTS_MODE_FILE="/tmp/mock_content_exists_mode"

function select-oci-auth() {
  echo "Mock select-oci-auth called with: $*"
  : > "${AUTHFILE}"
}

function oras() {
  echo "Mock oras called with: $*"
  echo $* >> $(params.dataDir)/mock_oras.txt
  local args="$*"

  if [[ "$*" == "pull --registry-config"* ]]; then
    output_file_dir=""
    echo "none" > "${CONTENT_EXISTS_MODE_FILE}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -o|--output)
          output_file_dir="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    mkdir -p "${output_file_dir}"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.aarch64.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.ppc64le.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.s390x.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.src.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.x86_64.rpm"
    touch "${output_file_dir}/hello-docs-2.12.1-6.fc44.noarch.rpm"
    mkdir -p "${output_file_dir}/logs"
    return 0
  fi
}

function rpm() {
  if [[ "${1-}" == "-qp" ]]; then
    local file_path=""
    local filename base nvra namever version_with_epoch name epoch version release arch

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -qp)
          shift
          ;;
        --qf)
          shift 2
          ;;
        *)
          file_path="$1"
          shift
          ;;
      esac
    done

    if [[ -z "${file_path}" ]]; then
      echo "mock rpm: missing rpm file path" >&2
      return 1
    fi

    filename="$(basename "${file_path}")"
    base="${filename%.rpm}"
    arch="${base##*.}"
    nvra="${base%.*}"
    release="${nvra##*-}"
    namever="${nvra%-*}"
    version_with_epoch="${namever##*-}"
    name="${namever%-*}"
    epoch="0"
    if [[ "${version_with_epoch}" == *:* ]]; then
      epoch="${version_with_epoch%%:*}"
      version="${version_with_epoch#*:}"
    else
      version="${version_with_epoch}"
    fi

    printf '%s|%s|%s|%s|%s\n' "${name}" "${epoch}" "${version}" "${release}" "${arch}"
    return 0
  fi

  command rpm "$@"
}

function internal-request() {
  echo "Mock internal-request called with: $*"
  echo "$*" >> $(params.dataDir)/mock_internal_request.txt

  IR_NAME="mock-ir-$(date +%s)"

  # Just print the created message - the kubectl mock will handle status queries
  echo "internalrequest.appstudio.redhat.com/${IR_NAME} created"
}

function kubectl() {
  UNRELEASED_RPMS=$(echo -n '[{"name":"test-component","purl":"pkg:rpm/redhat/hello@2.12.1-6.fc44?arch=x86_64","sha256":"abc123","rpmname":"hello","epoch":"0","version":"2.12.1","release":"6.fc44","arch":"x86_64","repository_name":"x86_64"}]' | gzip -c | base64 -w 0)
  IN_ADVISORY_RPMS=$(echo -n '[]' | gzip -c | base64 -w 0)

  MOCK_RESULTS='{
    "result": "Success",
    "unreleased_rpms": "'"$UNRELEASED_RPMS"'",
    "in_advisory_rpms": "'"$IN_ADVISORY_RPMS"'",
    "internalRequestPipelineRunName": "test-pipeline-run",
    "internalRequestTaskRunName": "test-task-run",
    "advisory_url": "",
    "advisory_internal_url": ""
  }'

  if [[ "$*" == *"get internalrequest"*"-o=jsonpath={.status.results}"* ]]; then
    echo "$MOCK_RESULTS"
  elif [[ "$*" == *"get internalrequest"*"-o json"* ]]; then
    echo '{
      "apiVersion": "appstudio.redhat.com/v1alpha1",
      "kind": "InternalRequest",
      "metadata": {"name": "mock-ir"},
      "status": {
        "results": '"$MOCK_RESULTS"',
        "conditions": [{"type": "Succeeded", "status": "True"}]
      }
    }'
  elif [[ "$*" == *"get internalrequest"*"-o yaml"* ]]; then
    echo "apiVersion: appstudio.redhat.com/v1alpha1"
    echo "kind: InternalRequest"
    echo "metadata:"
    echo "  name: mock-ir"
    echo "status:"
    echo "  conditions:"
    echo "  - status: \"True\""
    echo "    type: Succeeded"
  else
    /usr/bin/kubectl "$@"
  fi
}

