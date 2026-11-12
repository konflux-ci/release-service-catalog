#!/usr/bin/env bash
# Fails if a release-service-utils image digest added by this PR's diff is
# older than MAX_AGE_DAYS. Only runs for changes targeting development, and
# is skipped on a revert since reverting is how we intentionally move back
# to an older image.

set -euo pipefail

max_age_days=4
max_age_seconds=$(( max_age_days * 86400 ))
now=$(date +%s)
digest_pattern='quay\.io/konflux-ci/release-service-utils@sha256:[a-f0-9]+'

# pull_request gives us a bare branch name, merge_group gives a full "refs/heads/..." ref
BASE_REF="${RAW_BASE_REF#refs/heads/}"

if [[ "${BASE_REF}" != "development" ]]; then
  echo "Base branch is ${BASE_REF}, not development: skipping image age check"
  exit 0
fi

echo "Checking that new release-service-utils image references are no older than ${max_age_days} days"

# checkout only fetches HEAD's history, so the base branch isn't available locally yet
git fetch --quiet origin "${BASE_REF}"
merge_base=$(git merge-base "origin/${BASE_REF}" HEAD)

if git log --format='%s' "${merge_base}..HEAD" | grep -qE '^(revert(\(.*\))?: |Revert ")'; then
  echo "Revert commit detected: skipping image age check"
  exit 0
fi

mapfile -t changed_yaml_files < <(git diff --name-only "${merge_base}" HEAD -- '*.yaml')

if [[ "${#changed_yaml_files[@]}" -eq 0 ]]; then
  echo "No changed YAML files"
  exit 0
fi

# YAML's "\<newline>" continuation joins a split value with no added space.
# Undo it here so a reference split that way still matches as one string.
unfold() {
  perl -0777 -pe 's/\\\n[ \t]*//g'
}

digests_at() {
  local rev="$1" file
  for file in "${changed_yaml_files[@]}"; do
    git show "${rev}:${file}" 2>/dev/null | unfold | grep -oP "${digest_pattern}" || true
  done
}

# Only digests this diff actually adds, not ones already present before it.
mapfile -t digests < <(comm -13 <(digests_at "${merge_base}" | sort -u) <(digests_at HEAD | sort -u))

if [[ "${#digests[@]}" -eq 0 ]]; then
  echo "No new image references introduced by this diff"
  exit 0
fi

is_fresh() {
  ref="$1"
  # just the hash: grep below still finds the file even if the hash is on its own line
  hash="${ref#*sha256:}"

  # These refs are multi-arch manifest lists, so skopeo needs to be told which
  # platform to resolve to before it can hand back a single image's metadata
  if ! created=$(skopeo inspect --override-os linux --override-arch amd64 "docker://${ref}" 2>&1 | jq -r '.Created'); then
    echo "ERROR: failed to inspect ${ref}"
    echo "  ${created}"
    grep -rl "${hash}" "${changed_yaml_files[@]}" 2>/dev/null | sed 's/^/  /'
    return 1
  fi

  created_ts=$(date -d "${created}" +%s)
  age_days=$(( (now - created_ts) / 86400 ))

  if (( now - created_ts > max_age_seconds )); then
    echo "ERROR: ${ref} is ${age_days} days old (max ${max_age_days}), built ${created}"
    grep -rl "${hash}" "${changed_yaml_files[@]}" 2>/dev/null | sed 's/^/  /'
    return 1
  fi

  echo "OK: ${ref} is ${age_days} days old"
  return 0
}

fail=0

for ref in "${digests[@]}"; do
  is_fresh "${ref}" || fail=1
done

exit "${fail}"
