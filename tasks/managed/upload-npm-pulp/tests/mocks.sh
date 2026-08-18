#!/usr/bin/env bash
set -euo pipefail

# HTTP-level mocks prepended to the production upload script.
# State/logs live under FILES_DIR so check-result can read them via the
# trusted artifact (TaskRun /tmp is not shared across pipeline tasks).

MOCK_PULP_DIR="${FILES_DIR}/.mock-pulp"
mkdir -p "${MOCK_PULP_DIR}"
MOCK_PULP_STATE="${MOCK_PULP_STATE:-${MOCK_PULP_DIR}/state.json}"
MOCK_PULP_VERSION_FILE="${MOCK_PULP_VERSION_FILE:-${MOCK_PULP_DIR}/version}"
MOCK_PULP_LOG="${MOCK_PULP_LOG:-${MOCK_PULP_DIR}/curl.log}"
# Must be exported: npm-pulp-upload is a subprocess that sees export -f curl
# but not unexported shell variables (and runs under set -u).
export MOCK_PULP_DIR MOCK_PULP_STATE MOCK_PULP_VERSION_FILE MOCK_PULP_LOG

if [[ ! -f "${MOCK_PULP_STATE}" ]]; then
  echo '{}' > "${MOCK_PULP_STATE}"
fi
if [[ ! -f "${MOCK_PULP_VERSION_FILE}" ]]; then
  echo "1" > "${MOCK_PULP_VERSION_FILE}"
fi

_mock_version() {
  cat "${MOCK_PULP_VERSION_FILE}"
}

_bump_version() {
  local v
  v="$(_mock_version)"
  echo "$((v + 1))" > "${MOCK_PULP_VERSION_FILE}"
}

_pkg_key() {
  printf '%s@%s' "${1}" "${2}"
}

_arg_value() {
  local key="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${key}="* ]]; then
      printf '%s' "${arg#${key}=}"
      return 0
    fi
  done
  return 1
}

_file_from_form() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == file=@* ]]; then
      printf '%s' "${arg#file=@}"
      return 0
    fi
  done
  return 1
}

function curl() {
  local safe=("$@")
  local i
  for i in "${!safe[@]}"; do
    if [[ "${safe[i]}" == -u || "${safe[i]}" == --user ]]; then
      safe[i]="-u"
      if [[ -n "${safe[i+1]:-}" ]]; then
        safe[i+1]="***:***"
      fi
    fi
  done
  echo "curl ${safe[*]}" >> "${MOCK_PULP_LOG}"

  local args=("$@")
  local joined="${args[*]}"

  # Repository list / refresh (match URL path, not repository_version= query values)
  if [[ "${joined}" == *"/repositories/npm/npm/"* \
     && "${joined}" != *"/content/"* \
     && "${joined}" != *"modify/"* ]]; then
    local ver
    ver="$(_mock_version)"
    jq -nc --argjson ver "${ver}" '{
      results: [{
        name: "npm-registry",
        pulp_href: "/api/pulp/test-domain/api/v3/repositories/npm/npm/repo-uuid/",
        latest_version_href: ("/api/pulp/test-domain/api/v3/repositories/npm/npm/repo-uuid/versions/\($ver)/")
      }]
    }'
    return 0
  fi

  # Optional file repository lookup for compliance sidecars
  if [[ "${joined}" == *"/repositories/file/file/"* \
     && "${joined}" != *"/content/"* ]]; then
    jq -nc '{
      results: [{
        name: "npm-compliance",
        pulp_href: "/api/pulp/test-domain/api/v3/repositories/file/file/file-repo-uuid/"
      }]
    }'
    return 0
  fi

  # Package upload
  if [[ "${joined}" == *"/content/npm/packages/upload/"* ]]; then
    local name version file_path sha key
    name="$(_arg_value name "${args[@]}" || true)"
    version="$(_arg_value version "${args[@]}" || true)"
    file_path="$(_file_from_form "${args[@]}" || true)"
    if [[ -z "${name}" || -z "${version}" || -z "${file_path}" || ! -f "${file_path}" ]]; then
      echo "mock curl: upload missing name/version/file" >&2
      return 22
    fi
    if [[ -f "${FILES_DIR}/.mock_upload_fail" ]]; then
      echo "mock curl: forced upload failure" >&2
      return 22
    fi
    sha="$(sha256sum "${file_path}" | awk '{print $1}')"
    key="$(_pkg_key "${name}" "${version}")"
    jq --arg key "${key}" --arg sha "${sha}" --arg name "${name}" --arg version "${version}" '
      .[$key] = {
        name: $name,
        version: $version,
        sha256: $sha,
        pulp_href: "/api/pulp/test-domain/api/v3/content/npm/packages/uploaded/",
        artifact: ("/api/pulp/test-domain/api/v3/artifacts/\($sha)/"),
        pulp_labels: {}
      }
    ' "${MOCK_PULP_STATE}" > "${MOCK_PULP_STATE}.tmp" \
      && mv "${MOCK_PULP_STATE}.tmp" "${MOCK_PULP_STATE}"
    _bump_version
    echo '{"pulp_href":"/api/pulp/test-domain/api/v3/content/npm/packages/uploaded/"}'
    return 0
  fi

  # Add uploaded content to the repository (async task)
  if [[ "${joined}" == *"modify/"* ]]; then
    _bump_version
    echo '{"task":"/api/pulp/test-domain/api/v3/tasks/task-uuid/"}'
    return 0
  fi

  if [[ "${joined}" == *"/tasks/"* ]]; then
    echo '{"state":"completed"}'
    return 0
  fi

  # Artifact GET
  if [[ "${joined}" == *"/artifacts/"* ]]; then
    local sha="" arg from_state
    for arg in "${args[@]}"; do
      if [[ "${arg}" == *"/artifacts/"* ]]; then
        sha="${arg#*/artifacts/}"
        sha="${sha%%/*}"
        break
      fi
    done
    if [[ "${sha}" == "conflict" ]]; then
      echo '{"sha256":"0000000000000000000000000000000000000000000000000000000000000000"}'
      return 0
    fi
    from_state="$(jq -r --arg sha "${sha}" '
      [.[].sha256] | map(select(. == $sha)) | first // empty
    ' "${MOCK_PULP_STATE}")"
    jq -nc --arg sha "${from_state:-${sha}}" '{sha256: $sha}'
    return 0
  fi

  # Label updates — must run before content-detail; set_label URLs contain
  # /content/npm/packages/<id>/set_label/ and would otherwise match that branch.
  if [[ "${joined}" == *"set_label/"* ]]; then
    local arg href="" key="" value=""
    for arg in "${args[@]}"; do
      if [[ "${arg}" == *set_label/* ]]; then
        href="${arg%%set_label/*}"
        # Strip scheme/host if curl was given a full URL.
        if [[ "${href}" == *"/api/pulp/"* ]]; then
          href="/api/pulp/${href#*/api/pulp/}"
        fi
      fi
      if [[ "${arg}" == '{'*"key"*'}' ]]; then
        key="$(jq -r '.key // empty' <<<"${arg}")"
        value="$(jq -r '.value // empty' <<<"${arg}")"
      fi
    done
    if [[ -n "${href}" && -n "${key}" ]]; then
      jq --arg href "${href}" --arg key "${key}" --arg value "${value}" '
        to_entries
        | map(
            (.value.pulp_href // "") as $h
            | if ($h != "" and ($href | (endswith($h) or contains($h))))
              then .value.pulp_labels[$key] = $value
              else .
              end
          )
        | from_entries
      ' "${MOCK_PULP_STATE}" > "${MOCK_PULP_STATE}.tmp" \
        && mv "${MOCK_PULP_STATE}.tmp" "${MOCK_PULP_STATE}"
    fi
    echo '{}'
    return 0
  fi

  # Content detail GET by href (path contains /packages/<id>/, no list filters)
  if [[ "${joined}" == *"/content/npm/packages/"* \
     && "${joined}" != *"/upload/"* \
     && "${joined}" != *"set_label/"* \
     && "${joined}" != *"--data-urlencode"* ]]; then
    local entry
    entry="$(jq -c '
      to_entries | map(.value) | .[0] // empty
    ' "${MOCK_PULP_STATE}")"
    # Prefer href match when possible
    local arg href_match=""
    for arg in "${args[@]}"; do
      if [[ "${arg}" == *"/content/npm/packages/"* ]]; then
        href_match="$(jq -c --arg arg "${arg}" '
          to_entries
          | map(select(
              .value.pulp_href as $h
              | ($arg | (endswith($h) or contains($h)))
            ))
          | .[0].value // empty
        ' "${MOCK_PULP_STATE}")"
        break
      fi
    done
    if [[ -n "${href_match}" ]]; then
      jq -nc --argjson entry "${href_match}" '$entry'
      return 0
    fi
    if [[ -n "${entry}" ]]; then
      jq -nc --argjson entry "${entry}" '$entry'
      return 0
    fi
    echo '{}'
    return 0
  fi

  # Content list / existence. RH Pulp has no version= filter; the client
  # lists by name and filters version in jq. Keep version= lookup so the
  # currently pinned plumbing-utils image still works.
  if [[ "${joined}" == *"/content/npm/packages/"* ]]; then
    local name version key entry
    name="$(_arg_value name "${args[@]}" || true)"
    version="$(_arg_value version "${args[@]}" || true)"
    if [[ -n "${version}" ]]; then
      key="$(_pkg_key "${name}" "${version}")"
      entry="$(jq -c --arg key "${key}" '.[$key] // empty' "${MOCK_PULP_STATE}")"
      if [[ -z "${entry}" ]]; then
        echo '{"count":0,"next":null,"results":[]}'
        return 0
      fi
      jq -nc --argjson entry "${entry}" '{count:1, next:null, results:[$entry]}'
      return 0
    fi
    jq -nc --arg name "${name}" --slurpfile state "${MOCK_PULP_STATE}" '
      ($state[0] | to_entries | map(.value) | map(select(.name == $name))) as $r
      | {count: ($r | length), next: null, results: $r}
    '
    return 0
  fi

  if [[ "${joined}" == *"/content/file/files/"* ]]; then
    if [[ "${joined}" != *"relative_path="* ]]; then
      echo "mock curl: file upload missing relative_path" >&2
      return 22
    fi
    echo '{"pulp_href":"/api/pulp/test-domain/api/v3/content/file/files/sidecar/"}'
    return 0
  fi

  echo "mock curl: unhandled request: ${joined}" >&2
  return 22
}

# Export mocks so npm-pulp-upload (subprocess) sees them.
export -f curl _mock_version _bump_version _pkg_key _arg_value _file_from_form
