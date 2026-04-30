#!/usr/bin/env bash
set -eux

# mocks to be injected into task step scripts
function internal-request() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-request "$@" -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function internal-pipelinerun() {
  echo Mock internal-request called with: $*
  echo $* >> $(params.dataDir)/mock_internal-request.txt

  # set to async
  /home/utils/internal-pipelinerun "$@" -s false

  # mimic the sync output
  echo "Sync flag set to true. Waiting for the InternalRequest to be completed."
  sleep 2
}

function find_signatures() {
  echo $* >> "$(params.dataDir)/mock_find_signatures.txt"

  reference=$(echo $* | grep -oP 'repository \K\w+')
  file=$(echo $* | grep -oP 'output_file (.+)$' | cut -f2 -d' ')
  manifest_digest=$(printf '%s\n' "$*" | sed -n 's/.*--manifest_digest \([^ ]*\).*/\1/p')
  touch "${file}"

  datadir="$(params.dataDir)"
  if [ -f "${datadir}/.mock_find_signatures_always_fail" ]; then
    return 1
  fi

  # First invocation per digest fails; second succeeds (exercises signatureLookupMaxAttempts retries)
  if [ -f "${datadir}/.mock_find_signatures_fail_first_attempt" ]; then
    digest_key="${manifest_digest//:/_}"
    ctr_file="${datadir}/.fs_attempt_${digest_key}"
    n=$(cat "${ctr_file}" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "${n}" > "${ctr_file}"
    if [ "${n}" -eq 1 ]; then
      return 1
    fi
  fi

  if [ "${repository}" == "already/signed" ]; then
    echo "registry.redhat.io/already/signed:some-prefix" >> "${file}"
    echo "registry.access.redhat.com/already/signed:some-prefix" >> "${file}"
  fi
}
