#!/usr/bin/env bash
set -ex

# Reuse the same mocks as push-rpms-to-pulp tests, since this task calls the same tools.
# These mocks are injected into the task step script by pre-apply-task-hook.sh.

UPLOAD_COUNTER=0
UPLOAD_FAIL_ONCE_ENABLED=0
UPLOAD_FAIL_ONCE_ENABLED_FILE="/tmp/mock_upload_failonce_enabled"
UPLOAD_FAIL_ONCE_DONE_FILE="/tmp/mock_upload_failonce_done"
CONTENT_EXISTS_MODE_FILE="/tmp/mock_content_exists_mode"

function curl() {
  local args="$*"

  if [[ "$args" == *"sso.redhat.com"* ]]; then
    echo "token_request" >> $(params.dataDir)/mock_sso.txt
    echo '{"access_token": "mock-access-token", "expires_in": 3600}'
  elif [[ "$args" == *"/api/pulp/mock/api/v3/repositories/rpm/rpm/"* ]] && [[ "$args" != *"name="* ]]; then
    echo '{"latest_version_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/mock-repo-uuid/versions/1/"}'
  elif [[ "$args" == *"/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/"* ]]; then
    echo '{"pulp_href": "/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/", "artifact": "/api/pulp/mock/api/v3/artifacts/mock-artifact-uuid/"}'
  elif [[ "$args" == *"/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/"* ]]; then
    echo '{"pulp_href": "/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/", "artifact": "/api/pulp/mock/api/v3/artifacts/mock-artifact-uuid/"}'
  elif [[ "$args" == *"/api/pulp/mock/api/v3/artifacts/"* ]]; then
    echo '{"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}'
  elif [[ "$args" == *"/content/rpm/packages/"* ]]; then
    mode="none"
    if [[ -f "${CONTENT_EXISTS_MODE_FILE}" ]]; then
      mode="$(cat "${CONTENT_EXISTS_MODE_FILE}")"
    fi
    echo "content_query mode=${mode} url=${args}" >> $(params.dataDir)/mock_content_queries.txt
    if [[ "${mode}" == "all" ]]; then
      echo '{"count": 1, "results": [{"pulp_href": "/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/", "artifact": "/api/pulp/mock/api/v3/artifacts/mock-artifact-uuid/"}]}'
    else
      echo '{"count": 0, "results": []}'
    fi
  elif [[ "$args" == *"repositories/rpm/rpm"* && "$args" == *"name="* ]]; then
    # Handle both old-style arch names and new repository_id based names
    if [[ "$args" == *"name=source"* ]] || [[ "$args" == *"name=rpm-source"* ]]; then
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/source-uuid/"}]}'
    elif [[ "$args" == *"name=x86_64"* ]] || [[ "$args" == *"name=rpm-x86_64"* ]]; then
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/x86_64-uuid/"}]}'
    elif [[ "$args" == *"name=aarch64"* ]] || [[ "$args" == *"name=rpm-aarch64"* ]]; then
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/aarch64-uuid/"}]}'
    elif [[ "$args" == *"name=ppc64le"* ]] || [[ "$args" == *"name=rpm-ppc64le"* ]]; then
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/ppc64le-uuid/"}]}'
    elif [[ "$args" == *"name=s390x"* ]] || [[ "$args" == *"name=rpm-s390x"* ]]; then
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/s390x-uuid/"}]}'
    else
      echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/default-uuid/"}]}'
    fi
  elif [[ "$args" == *"modify"* ]]; then
    echo '{"task": "/api/pulp/mock/api/v3/tasks/mock-task-id/"}'
  else
    command curl "$@"
  fi
}

function select-oci-auth() {
  echo "Mock select-oci-auth called with: $*"
  # The real helper writes registry credentials to $AUTHFILE; tests don't require it.
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

    if [[ "$args" == *"quay.io/test/alreadyexists"* ]]; then
      echo "all" > "${CONTENT_EXISTS_MODE_FILE}"
    elif [[ "$args" == *"quay.io/test/digestmismatch"* ]]; then
      echo "all" > "${CONTENT_EXISTS_MODE_FILE}"
      printf '%s\n' "not-empty" > "${output_file_dir}/hello-2.12.1-6.fc44.x86_64.rpm"
      mkdir -p "${output_file_dir}/logs"
      touch "${output_file_dir}/logs/hello-2.12.1-6.fc44.x86_64.rpm.log"
      return 0
    elif [[ "$args" == *"quay.io/test/manyrpms"* ]]; then
      # Generate many RPMs to test "arg list too long" fix.
      # Linux MAX_ARG_STRLEN is 128KB per argument. With 600 RPMs (~144KB JSON),
      # the old --argjson approach fails; the --slurpfile fix handles this.
      mkdir -p "${output_file_dir}"
      for i in $(seq 1 600); do
        touch "${output_file_dir}/glibc-subpkg${i}-2.38-${i}.fc44.x86_64.rpm"
      done
      mkdir -p "${output_file_dir}/logs"
      return 0
    elif [[ "$args" == *"quay.io/test/noarchonly"* ]]; then
      # Create ONLY noarch RPMs - no arch-specific RPMs
      # This tests that DEFAULT_ARCHITECTURES is used for targeting
      mkdir -p "${output_file_dir}"
      touch "${output_file_dir}/hello-docs-2.12.1-6.fc44.noarch.rpm"
      touch "${output_file_dir}/hello-man-2.12.1-6.fc44.noarch.rpm"
      mkdir -p "${output_file_dir}/logs"
      touch "${output_file_dir}/logs/hello-docs-2.12.1-6.fc44.noarch.rpm.log"
      return 0
    fi

    # Default: create empty RPM files
    mkdir -p "${output_file_dir}"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.aarch64.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.ppc64le.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.s390x.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.src.rpm"
    touch "${output_file_dir}/hello-2.12.1-6.fc44.x86_64.rpm"
    touch "${output_file_dir}/hello-docs-2.12.1-6.fc44.noarch.rpm"
    mkdir -p "${output_file_dir}/logs"
    touch "${output_file_dir}/logs/hello-2.12.1-6.fc44.x86_64.rpm.log"
    return 0
  fi
}

# The unit tests create dummy RPM files (empty placeholders). The production task
# parses NEVRA from the RPM header via `rpm -qp`, so we mock that behavior here.
function rpm() {
  # Only mock RPM header queries used by parse_nevra() (`rpm -qp --qf ... <file>`).
  if [[ "${1-}" == "-qp" ]]; then
    local file_path=""
    local filename base nvra namever version_with_epoch name epoch version release arch

    # Extract the RPM path from args (ignore query flags/format).
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
