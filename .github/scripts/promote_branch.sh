#!/usr/bin/env bash

# This script promotes branches in the release-service-catalog repository.
#
# The script promotes the development content into the staging branch, or the staging
# content into the production branch. It starts by performing the following checks, then
# it performs a git push. There is no pull request.
#
# Checks:
#   - If there is content in the staging branch that is not yet in the production branch, the
#     script will not git push to add more content to the staging branch. This can be overridden with
#     --force-to-staging true
#   - If promoting to production and the content has not been in the staging branch for at least 7 days,
#     the script will exit without doing a push. Content is expected to sit in staging for at least a week
#     to provide sufficient testing time. This can be overridden with --override true
#
# Prerequisities:
#   - An environment variable GITHUB_TOKEN is defined that provides access to the user's account. See
#     https://github.com/konflux-ci/release-service-utils/blob/main/ci/promote-overlay/README.md#setup for help.
#   - curl, git and jq installed.

set -e

# GitHub repository details
ORG="konflux-ci"
REPO="release-service-catalog"

OPTIONS=$(getopt --long "promotion-type:,force-to-staging:,override:,dry-run:,help" -o "p:,h" -- "$@")
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -p|--promotion-type)
            PROMOTION_TYPE="$2"
            shift 2
            ;;
        --force-to-staging)
            FORCE_TO_STAGING="$2"
            shift 2
            ;;
        --override)
            OVERRIDE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit
            ;;
        --)
            shift
            break
            ;;
        *) echo "Error: Unexpected option: $1" % >2
    esac
done

print_help(){
    echo "Usage: $0 --branches branch1-to-branch2 [--force-to-staging false] [--override false] [--dry-run false]"
    echo
    echo "  --promotion-type:   The type of promotion to perform. Either development-to-staging"
    echo "                      or staging-to-production."
    echo "  --force-to-staging: If passed with value true, allow promotion to staging even"
    echo "                      if staging and production differ."
    echo "  --override:         If passed with value true, allow promotion to production"
    echo "                      even if the change has not been in staging for one week."
    echo "  --dry-run:          If passed with value true, print out the changes that would"
    echo "                      be promoted but do not git push or delete the temp repo."
    echo
    echo "  --promotion-type has to be specified."
}

check_if_branch_differs() {
    ACTUAL_DIFFERENT_LINES=$(git diff --numstat origin/$1 | wc -l)
    if [ $ACTUAL_DIFFERENT_LINES -ne 0 ] ; then
        echo "Lines differ in branch $1"
        echo "Actual differing lines: $(git diff --numstat origin/$1)"
        exit 1
    fi
}

check_if_any_commits_in_last_week() {
    NEW_COMMITS=$(git log --oneline --since="$(date --date="6 days ago" +%Y-%m-%d)" | wc -l)
    if [ $NEW_COMMITS -ne 0 ] ; then
        echo "There are commits in staging that are less than a week old. Blocking promotion to production"
        echo "Commits less than a week old: $(git log --oneline --since="$(date --date="6 days ago" +%Y-%m-%d)")"
        exit 1
    fi
}

# GraphQL function to fetch all PRs in a time range
fetch_prs_graphql() {
    local since_date="$1"
    local page_size="${2:-100}"
    local cursor="${3:-null}"

    # Calculate cursor parameter for pagination
    local cursor_param=""
    if [ "$cursor" != "null" ]; then
        cursor_param=", after: \"$cursor\""
    fi

    # GraphQL query to fetch PRs with commits
    local query=$(cat <<EOF
{
  "query": "query {
    repository(owner: \"$ORG\", name: \"$REPO\") {
      pullRequests(first: $page_size, states: MERGED, orderBy: {field: UPDATED_AT, direction: DESC}$cursor_param) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          number
          title
          url
          mergedAt
          commits(first: 250) {
            nodes {
              commit {
                oid
                messageHeadline
              }
            }
          }
        }
      }
    }
  }"
}
EOF
)

    # Make GraphQL request
    curl -s -X POST \
        -H "Authorization: bearer $token" \
        -H "Content-Type: application/json" \
        --data "$query" \
        https://api.github.com/graphql
}

# Function to get all PRs with pagination
get_all_prs_since_date() {
    local since_date="$1"
    local all_prs="[]"
    local has_next_page=true
    local cursor="null"

    echo "Fetching all merged PRs since $since_date using GraphQL..." >&2

    while [ "$has_next_page" = true ]; do
        echo "Fetching page (cursor: $cursor)..." >&2

        local response=$(fetch_prs_graphql "$since_date" 100 "$cursor")

        # Check for GraphQL errors
        local errors=$(echo "$response" | jq -r '.errors // empty')
        if [ -n "$errors" ]; then
            echo "GraphQL Error: $errors" >&2
            exit 1
        fi

        # Extract PR data
        local page_prs=$(echo "$response" | jq -r '.data.repository.pullRequests.nodes')

        # Filter PRs by date (since GraphQL doesn't support date filtering directly)
        local filtered_prs=$(echo "$page_prs" | jq --arg since_date "$since_date" '
            map(select(.mergedAt >= $since_date))
        ')

        # If no PRs match our date criteria, we can stop
        local filtered_count=$(echo "$filtered_prs" | jq 'length')
        if [ "$filtered_count" -eq 0 ]; then
            echo "No more PRs found since $since_date, stopping pagination." >&2
            break
        fi

        # Merge with existing PRs
        all_prs=$(echo "$all_prs $filtered_prs" | jq -s 'add')

        # Check pagination
        has_next_page=$(echo "$response" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage')
        cursor=$(echo "$response" | jq -r '.data.repository.pullRequests.pageInfo.endCursor')

        echo "Found $(echo "$filtered_prs" | jq 'length') PRs in this page" >&2
    done

    echo "$all_prs"
}

# Function to match commits to PRs locally
find_prs_for_commits() {
    local commits_json="$1"
    local prs_json="$2"

    # Create a lookup map of commit SHA to PR
    local commit_to_pr_map=$(echo "$prs_json" | jq -r '
        [
            .[] as $pr |
            $pr.commits.nodes[] |
            {
                commit: .commit.oid,
                pr: {
                    number: $pr.number,
                    title: $pr.title,
                    url: $pr.url,
                    mergedAt: $pr.mergedAt
                }
            }
        ] |
        group_by(.commit) |
        map({key: .[0].commit, value: .[0].pr}) |
        from_entries
    ')

    # Match commits to PRs
    echo "$commits_json" | jq --argjson map "$commit_to_pr_map" '
        map(. as $commit | $map[$commit] // {commit: $commit, pr: null})
    '
}

if [ -z "${PROMOTION_TYPE}" ]; then
    echo -e "Error: missing '--promotion-type' argument\n"
    print_help
    exit 1
fi
if [ "${PROMOTION_TYPE}" == development-to-staging ]; then
    SOURCE_BRANCH=development
    TARGET_BRANCH=staging
elif [ "${PROMOTION_TYPE}" == staging-to-production ]; then
    SOURCE_BRANCH=staging
    TARGET_BRANCH=production
else
    echo "Invalid promotion type. Only 'development-to-staging' and 'staging-to-production' are allowed"
    print_help
    exit 1
fi
if [ -z "${GITHUB_TOKEN}" ]; then
    echo -e "Error: missing 'GITHUB_TOKEN' environment variable\n"
    print_help
    exit 1
fi

# Personal access token with appropriate permissions
token="${GITHUB_TOKEN}"

# Clone the repository
tmpDir=$(mktemp -d)
releaseServiceCatalogDir=${tmpDir}/release-service-catalog
mkdir -p ${releaseServiceCatalogDir}

echo -e "---\nPromoting release-service-catalog ${SOURCE_BRANCH} to ${TARGET_BRANCH}\n---\n"

git clone "https://oauth2:$GITHUB_TOKEN@github.com/$ORG/$REPO.git" ${releaseServiceCatalogDir}
cd ${releaseServiceCatalogDir}

# A change cannot go into production if the changes in staging are less than a week old
if [[ "${TARGET_BRANCH}" == "production" && "${OVERRIDE}" != "true" ]] ; then
    git checkout origin/staging
    check_if_any_commits_in_last_week
fi

# A change cannot go into staging if staging and production differ
if [[ "${TARGET_BRANCH}" == "staging" && "${FORCE_TO_STAGING}" != "true" ]] ; then
    git checkout origin/staging
    check_if_branch_differs production
fi

echo "Included PRs:"

# Get commits to be promoted
COMMITS=($(git rev-list --first-parent --ancestry-path origin/"$TARGET_BRANCH"'...'origin/"$SOURCE_BRANCH"))

if [ ${#COMMITS[@]} -eq 0 ]; then
    echo "No commits to promote from $SOURCE_BRANCH to $TARGET_BRANCH"
    if [ "${DRY_RUN}" == "true" ] ; then
        exit
    fi
    exit 0
fi

# Get the oldest commit date to use as our since date for PR fetching
OLDEST_COMMIT=${COMMITS[-1]}
OLDEST_COMMIT_DATE=$(git show -s --format=%ci "$OLDEST_COMMIT" | cut -d' ' -f1)

echo "Fetching PRs since $OLDEST_COMMIT_DATE (oldest commit being promoted)"

# Fetch all PRs since the oldest commit date using GraphQL
ALL_PRS=$(get_all_prs_since_date "$OLDEST_COMMIT_DATE")

echo "Found $(echo "$ALL_PRS" | jq 'length') PRs since $OLDEST_COMMIT_DATE"

# Convert commits array to JSON for processing
COMMITS_JSON=$(printf '%s\n' "${COMMITS[@]}" | jq -R . | jq -s .)

# Find matching PRs for our commits
MATCHED_RESULTS=$(find_prs_for_commits "$COMMITS_JSON" "$ALL_PRS")

# Display results
echo "$MATCHED_RESULTS" | jq -r '
    .[] |
    if .pr then
        "PR #\(.pr.number): \(.pr.title)\n  URL: \(.pr.url)\n  Merged: \(.pr.mergedAt)\n  Commit: \(.commit)"
    else
        "Commit \(.commit): No associated PR found"
    end
'

# Show git log for each commit for additional context
echo -e "\nCommit details:"
for COMMIT in "${COMMITS[@]}"; do
  git show --oneline --no-patch $COMMIT
done

if [ "${DRY_RUN}" == "true" ] ; then
    exit
fi

git checkout $SOURCE_BRANCH
git push origin $SOURCE_BRANCH:$TARGET_BRANCH

cd -
rm -rf ${tmpDir}
