#!/usr/bin/env bash
#
# Summary:
#   Creates or updates the sticky ITS results comment on a release-service-catalog PR.
#
# Parameters:
#   $1: repo_name  - The GitHub repository name (for example, "owner/repo").
#   $2: pr_number  - The pull request number.
#
# Environment Variables:
#   GITHUB_TOKEN            - GitHub token with permission to read and update PR comments.
#   RUN_TEST_METADATA_JSON  - Compact JSON from run-test.sh with:
#                             its_name, result, failure_label, details_url, details_text.

set -euo pipefail

MARKER="<!-- release-service-catalog-its-results:v1 -->"
STATE_PREFIX="<!-- release-service-catalog-its-results-state: "
STATE_SUFFIX=" -->"
MAX_UPDATE_ATTEMPTS=5
GITHUB_API_STATUS=""
GITHUB_API_BODY=""
GITHUB_LOGIN=""

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "🔴 error: missing env var GITHUB_TOKEN" >&2
  exit 1
fi

repo_name="${1:-}"
if [ -z "${repo_name}" ]; then
  echo "🔴 error: missing parameter repo_name" >&2
  exit 1
fi

pr_number="${2:-}"
if [ -z "${pr_number}" ]; then
  echo "🔴 error: missing parameter pr_number" >&2
  exit 1
fi

metadata_json="${RUN_TEST_METADATA_JSON:-}"
if ! jq -e . >/dev/null 2>&1 <<< "${metadata_json}"; then
  echo "No valid run-test metadata found; skipping PR results comment update." >&2
  exit 0
fi

its_name=$(jq -r '.its_name // ""' <<< "${metadata_json}")
its_key=$(jq -r '.its_key // .its_name // ""' <<< "${metadata_json}")
result=$(jq -r '.result // ""' <<< "${metadata_json}")
if [ -z "${its_name}" ] || [ -z "${its_key}" ] || [ -z "${result}" ]; then
  echo "run-test metadata is missing its_name, its_key, or result; skipping PR results comment update." >&2
  exit 0
fi

case "${result}" in
  FAILURE|SUCCESS|SKIPPED)
    ;;
  *)
    echo "run-test metadata result ${result} is not final; skipping PR results comment update." >&2
    exit 0
    ;;
esac

html_escape() {
  local escaped="$1"
  escaped=${escaped//&/&amp;}
  escaped=${escaped//</&lt;}
  escaped=${escaped//>/&gt;}
  escaped=${escaped//\"/&quot;}
  printf '%s' "${escaped//$'\n'/<br>}"
}

encode_state() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

decode_state() {
  printf '%s' "$1" | base64 --decode
}

github_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local api_url="https://api.github.com/repos/${repo_name}/${endpoint}"
  local response_file
  local curl_status=0

  github_api_request "${method}" "${api_url}" "${data}"
}

github_api_root() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local api_url="https://api.github.com/${endpoint}"
  local response_file
  local curl_status=0

  github_api_request "${method}" "${api_url}" "${data}"
}

github_api_request() {
  local method="$1"
  local api_url="$2"
  local data="${3:-}"
  local response_file
  local curl_status=0

  response_file=$(mktemp)

  if [ -n "${data}" ]; then
    GITHUB_API_STATUS=$(curl -sS -o "${response_file}" -w '%{http_code}' \
      -X "${method}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api_url}" \
      -d "${data}") || curl_status=$?
  else
    GITHUB_API_STATUS=$(curl -sS -o "${response_file}" -w '%{http_code}' \
      -X "${method}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api_url}") || curl_status=$?
  fi

  GITHUB_API_BODY=$(cat "${response_file}")
  rm -f "${response_file}"

  if [ "${curl_status}" -ne 0 ]; then
    GITHUB_API_STATUS="curl-${curl_status}"
    return 1
  fi

  printf '%s' "${GITHUB_API_BODY}"
  [[ "${GITHUB_API_STATUS}" == 2* ]]
}

github_api_error_message() {
  if jq -e . >/dev/null 2>&1 <<< "${GITHUB_API_BODY}"; then
    jq -r '
      .message // .error // .errors[0].message // tostring
    ' <<< "${GITHUB_API_BODY}"
  else
    printf '%s' "${GITHUB_API_BODY}"
  fi
}

get_github_login() {
  local user_json

  if [ -n "${GITHUB_LOGIN}" ]; then
    printf '%s' "${GITHUB_LOGIN}"
    return 0
  fi

  if ! github_api_root GET "user" >/dev/null; then
    echo "🔴 error: failed to get GitHub user (status ${GITHUB_API_STATUS}): $(github_api_error_message)" >&2
    return 1
  fi
  user_json="${GITHUB_API_BODY}"

  GITHUB_LOGIN=$(jq -r '.login // ""' <<< "${user_json}")
  if [ -z "${GITHUB_LOGIN}" ]; then
    echo "🔴 error: GitHub user response did not include a login." >&2
    return 1
  fi

  printf '%s' "${GITHUB_LOGIN}"
}

find_existing_comment() {
  local page=1
  local comments_json matching_comment count github_login

  if ! github_login=$(get_github_login); then
    return 2
  fi

  while true; do
    if ! github_api GET "issues/${pr_number}/comments?per_page=100&page=${page}" >/dev/null; then
      echo "🔴 error: failed to list PR comments (status ${GITHUB_API_STATUS}): $(github_api_error_message)" >&2
      return 2
    fi
    comments_json="${GITHUB_API_BODY}"
    matching_comment=$(jq -c \
      --arg marker "${MARKER}" \
      --arg github_login "${github_login}" '
      map(select(
        (.user.login // "") == $github_login
        and ((.body // "") | contains($marker))
      )) | last // empty' <<< "${comments_json}")
    if [ -n "${matching_comment}" ]; then
      printf '%s' "${matching_comment}"
      return 0
    fi

    count=$(jq 'length' <<< "${comments_json}")
    if [ "${count}" -lt 100 ]; then
      break
    fi
    page=$((page + 1))
  done

  return 1
}

extract_state_json() {
  local body="$1"
  local state_b64

  state_b64=$(printf '%s\n' "${body}" \
    | sed -n "s/^${STATE_PREFIX}\\(.*\\)${STATE_SUFFIX}\$/\\1/p" | head -n 1)
  if [ -z "${state_b64}" ]; then
    printf '[]'
    return 0
  fi

  decode_state "${state_b64}" 2>/dev/null || printf '[]'
}

merge_state() {
  local existing_state_json="$1"

  jq -cn \
    --argjson existing_state "${existing_state_json}" \
    --argjson current "${metadata_json}" '
      ($existing_state | map(select(
        ((.its_key // .its_name // "") != ($current.its_key // $current.its_name))
        and (
          (.its_key // "") == ""
          and (.its_name // "") == ($current.its_name // "")
        | not)
      ))) as $without_current
      | if $current.result == "FAILURE" then
          ($without_current + [{
            its_key: ($current.its_key // $current.its_name),
            its_name: $current.its_name,
            failure_label: ($current.failure_label // ""),
            details_url: ($current.details_url // ""),
            details_text: ($current.details_text // "")
          }]) | sort_by(.its_name)
        elif ($current.result == "SUCCESS" or $current.result == "SKIPPED") then
          $without_current | sort_by(.its_name)
        else
          $existing_state | sort_by(.its_name)
        end'
}

render_rows() {
  local state_json="$1"
  local row_json row_its_name row_failure_label row_details_url row_details_text
  local link_cell details_cell

  while IFS= read -r row_json; do
    row_its_name=$(jq -r '.its_name // ""' <<< "${row_json}")
    row_failure_label=$(jq -r '.failure_label // ""' <<< "${row_json}")
    row_details_url=$(jq -r '.details_url // ""' <<< "${row_json}")
    row_details_text=$(jq -r '.details_text // ""' <<< "${row_json}")

    link_cell=""
    if [[ "${row_details_url}" == http://* || "${row_details_url}" == https://* ]]; then
      link_cell="<a href=\"$(html_escape "${row_details_url}")\">Open</a>"
    fi

    details_cell=""
    if [ -n "${row_details_text}" ]; then
      details_cell="<details><summary>Show</summary>$(html_escape "${row_details_text}")</details>"
    fi

    printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$(html_escape "${row_its_name}")" \
      "$(html_escape "${row_failure_label}")" \
      "${link_cell}" \
      "${details_cell}"
  done < <(jq -c '.[]' <<< "${state_json}")
}

render_comment_body() {
  local state_json="$1"
  local state_b64 rows

  state_b64=$(encode_state "${state_json}")
  rows=$(render_rows "${state_json}")

  {
    echo "${MARKER}"
    echo "${STATE_PREFIX}${state_b64}${STATE_SUFFIX}"
    echo "## Release Service Catalog ITS failures"
    echo
    if [ "$(jq 'length' <<< "${state_json}")" -eq 0 ]; then
      echo "No failing ITS rows in the latest PR-triggered runs."
    else
      echo "<table>"
      echo "<thead><tr><th>ITS</th><th>Failure</th><th>PipelineRun</th><th>Details</th></tr></thead>"
      echo "<tbody>"
      printf '%s\n' "${rows}"
      echo "</tbody>"
      echo "</table>"
    fi
  }
}

state_matches_expected() {
  local state_json="$1"

  if [ "${result}" = "FAILURE" ]; then
    jq -e \
      --arg its_key "${its_key}" \
      --argjson current "${metadata_json}" '
        any(
          .[]?;
          (.its_key // .its_name // "") == $its_key
          and (.failure_label // "") == ($current.failure_label // "")
          and (.details_url // "") == ($current.details_url // "")
          and (.details_text // "") == ($current.details_text // "")
        )' <<< "${state_json}" >/dev/null
  elif [ "${result}" = "SUCCESS" ] || [ "${result}" = "SKIPPED" ]; then
    jq -e --arg its_key "${its_key}" '
      all(.[]?; (.its_key // .its_name // "") != $its_key)' <<< "${state_json}" >/dev/null
  else
    return 0
  fi
}

upsert_comment() {
  local attempt existing_comment existing_comment_id existing_body existing_state_json
  local updated_state_json updated_body payload refreshed_comment refreshed_state_json
  local read_status=0

  for attempt in $(seq 1 "${MAX_UPDATE_ATTEMPTS}"); do
    existing_comment=""
    existing_comment_id=""
    existing_body=""
    existing_state_json='[]'
    read_status=0
    if existing_comment=$(find_existing_comment); then
      existing_comment_id=$(jq -r '.id' <<< "${existing_comment}")
      existing_body=$(jq -r '.body // ""' <<< "${existing_comment}")
      existing_state_json=$(extract_state_json "${existing_body}")
      if ! jq -e . >/dev/null 2>&1 <<< "${existing_state_json}"; then
        existing_state_json='[]'
      fi
    else
      read_status=$?
      if [ "${read_status}" -eq 2 ]; then
        echo "⚠️ Warning: failed to read existing ITS results comment state on attempt ${attempt}/${MAX_UPDATE_ATTEMPTS}" >&2
        sleep 1
        continue
      fi
    fi

    updated_state_json=$(merge_state "${existing_state_json}")
    if [ -z "${existing_comment_id}" ] && [ "$(jq 'length' <<< "${updated_state_json}")" -eq 0 ]; then
      echo "No failing ITS rows and no existing results comment; nothing to do." >&2
      return 0
    fi

    updated_body=$(render_comment_body "${updated_state_json}")
    payload=$(jq -nc --arg body "${updated_body}" '{body: $body}')

    if [ -n "${existing_comment_id}" ]; then
      echo "Updating ITS results comment on PR #${pr_number} (attempt ${attempt}/${MAX_UPDATE_ATTEMPTS})" >&2
      if ! github_api PATCH "issues/comments/${existing_comment_id}" "${payload}" >/dev/null; then
        echo "⚠️ Warning: failed to update ITS results comment (status ${GITHUB_API_STATUS}): $(github_api_error_message)" >&2
        sleep 1
        continue
      fi
    else
      echo "Creating ITS results comment on PR #${pr_number} (attempt ${attempt}/${MAX_UPDATE_ATTEMPTS})" >&2
      if ! github_api POST "issues/${pr_number}/comments" "${payload}" >/dev/null; then
        echo "⚠️ Warning: failed to create ITS results comment (status ${GITHUB_API_STATUS}): $(github_api_error_message)" >&2
        sleep 1
        continue
      fi
    fi

    refreshed_comment=$(find_existing_comment || true)
    if [ -z "${refreshed_comment}" ]; then
      echo "⚠️ Warning: ITS results comment was not readable after update on attempt ${attempt}/${MAX_UPDATE_ATTEMPTS}" >&2
      sleep 1
      continue
    fi

    refreshed_state_json=$(extract_state_json "$(jq -r '.body // ""' <<< "${refreshed_comment}")")
    if jq -e . >/dev/null 2>&1 <<< "${refreshed_state_json}" \
      && state_matches_expected "${refreshed_state_json}"; then
      echo "ITS results comment is up to date." >&2
      return 0
    fi

    echo "⚠️ Warning: ITS results comment state did not match expected content on attempt ${attempt}/${MAX_UPDATE_ATTEMPTS}" >&2
    sleep 1
  done

  echo "⚠️ Warning: failed to update ITS results comment after ${MAX_UPDATE_ATTEMPTS} attempts" >&2
  return 1
}

upsert_comment
