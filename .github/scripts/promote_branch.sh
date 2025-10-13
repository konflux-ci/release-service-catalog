#!/usr/bin/env bash

# This script promotes branches in the release-service-catalog repository.
#
# The script promotes the development content into the staging branch, or the staging
# content into the production branch. It starts by performing the following checks, then
# it performs a git force push. There is no pull request.
#
# Checks:
#   - If there is content in the staging branch that is not yet in the production branch, the
#     script will not git push to add more content to the staging branch. This can be overridden with
#     --force-to-staging true
#   - If promoting to production and the content has not been in the staging branch for at least 7 days,
#     the script will exit without doing a push. Content is expected to sit in staging for at least six days
#     to provide sufficient testing time. This can be overridden with --override true
#
# Prerequisities:
#   - An environment variable GITHUB_TOKEN is defined that provides access to the user's account. See
#     https://github.com/konflux-ci/release-service-utils/blob/main/ci/promote-overlay/README.md#setup for help.
#   - curl, git and jq installed.
#
# Environment Variables:
#   GITHUB_TOKEN              - Required. GitHub token with repo access
#   GITHUB_GRAPHQL_PAGE_SIZE  - Optional. GraphQL page size (1-100, default: 100)

set -e

# GitHub repository details
ORG="konflux-ci"
REPO="release-service-catalog"
COMMIT_MAX_AGE_DAYS=6

# Personal access token with appropriate permissions
token="${GITHUB_TOKEN}"

# Parsed tickets JSON
PARSED_TICKETS_JSON='[]'

print_help(){
    echo "Usage: $0 --branches branch1-to-branch2 [--force-to-staging false] [--override false] [--dry-run false]"
    echo
    echo "  --promotion-type:   The type of promotion to perform. Either development-to-staging"
    echo "                      or staging-to-production."
    echo "  --force-to-staging: If passed with value true, allow promotion to staging even"
    echo "                      if staging and production differ."
    echo "  --override:         If passed with value true, allow promotion to production"
    echo "                      even if the change has not been in staging for six days."
    echo "  --dry-run:          If passed with value true, print out the changes that would"
    echo "                      be promoted but do not git push or delete the temp repo."
    echo
    echo "  --promotion-type has to be specified."
}

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
        *) echo "Error: Unexpected option: $1" >&2
            exit 1
    esac
done

# Function to check if the branch differs from the target branch
check_if_branch_differs() {
    ACTUAL_DIFFERENT_LINES=$(git diff --numstat "origin/$1" | wc -l)
    if [ "$ACTUAL_DIFFERENT_LINES" -ne 0 ] ; then
        echo "Lines differ in branch $1"
        echo "Actual differing lines:"
        git diff --numstat "origin/$1"
        exit 1
    fi
}

# Function to check if there are any commits in the last six days
check_if_any_commits_in_last_six_days() {
    NEW_COMMITS=$(git log --oneline --since="$(date --date="6 days ago" +%Y-%m-%d)" | wc -l)
    if [ "$NEW_COMMITS" -ne 0 ] ; then
        echo "There are commits in staging that are less than six days old. Blocking promotion to production"
        echo "Commits less than six days old:"
        git log --oneline  --no-decorate --since="$(date --date="6 days ago" +%Y-%m-%d)"
        exit 1
    fi
}

# Function to get all PRs since a given date with pagination
get_all_prs_since_date() {
    local since_date="$1"
    local all_prs="[]"
    local has_next_page=true
    local cursor="null"

    # Create a single temporary file for the entire function (reuse instead of creating new ones each iteration)
    local temp_merge_file=$(mktemp)

    echo "Fetching all merged PRs since $since_date using GraphQL..." >&2

    while [ "$has_next_page" = true ]; do
        echo "Fetching page (cursor: $cursor)..." >&2

        # Calculate cursor parameter for pagination
        local cursor_param=""
        if [ "$cursor" != "null" ]; then
            cursor_param=", after: \\\"$cursor\\\""
        fi

        # GraphQL query to fetch PRs with commits
        local page_size="${GITHUB_GRAPHQL_PAGE_SIZE:-100}"
        local query_string="query { repository(owner: \\\"$ORG\\\", name: \\\"$REPO\\\") { pullRequests(first: $page_size, states: MERGED, orderBy: {field: UPDATED_AT, direction: DESC}$cursor_param) { pageInfo { hasNextPage endCursor } nodes { number title url mergedAt mergeCommit { oid } labels(first: 20) { nodes { name color description } } commits(first: 250) { nodes { commit { oid messageHeadline } } } } } } }"
        local query="{\"query\": \"$query_string\"}"

        # Make GraphQL request
        local response=$(curl -s -X POST \
            -H "Authorization: bearer $token" \
            -H "Content-Type: application/json" \
            --data "$query" \
            https://api.github.com/graphql)

        # Check for GraphQL errors
        local errors=$(echo "$response" | jq -r '.errors // empty')
        if [ -n "$errors" ]; then
            echo "GraphQL Error: $errors" >&2
            exit 1
        fi

        # Extract PR data
        local page_prs=$(echo "$response" | jq -r '.data.repository.pullRequests.nodes // []')

        # Check if we got valid data
        if [ "$page_prs" = "null" ] || [ "$page_prs" = "" ]; then
            echo "No PR data returned from GraphQL API" >&2
            break
        fi

        # Filter PRs by date (since GraphQL doesn't support date filtering directly)
        local filtered_prs=$(echo "$page_prs" | jq --arg since_date "$since_date" '
            map(select(.mergedAt and (.mergedAt | split("T")[0] >= $since_date)))
        ')

        # If no PRs match our date criteria, we can stop
        local filtered_count=$(echo "$filtered_prs" | jq 'length')
        if [ "$filtered_count" -eq 0 ]; then
            echo "No more PRs found since $since_date, stopping pagination." >&2
            break
        fi

        # Merge with existing PRs (reuse temp file to avoid argument length limits)
        echo "$all_prs" > "$temp_merge_file"
        echo "$filtered_prs" >> "$temp_merge_file"
        all_prs=$(jq -s 'add' "$temp_merge_file")

        # Check pagination
        has_next_page=$(echo "$response" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage')
        cursor=$(echo "$response" | jq -r '.data.repository.pullRequests.pageInfo.endCursor')

        page_count=$(echo "$filtered_prs" | jq 'length')
        echo "Found $page_count PRs in this page (after date filtering)" >&2
    done

    # Cleanup temporary file
    rm "$temp_merge_file"

    echo "$all_prs"
}

# Function to match commits to PRs locally
find_prs_for_commits() {
    local commits_json="$1"
    local prs_json="$2"

    # Create a lookup map of commit SHA to PR (including both regular commits and merge commits)
    local commit_to_pr_map=$(echo "$prs_json" | jq -r '
        [
            .[] as $pr |
            (
                # Regular commits from the PR
                ($pr.commits.nodes[] | {
                    commit: .commit.oid,
                    pr: {
                        number: $pr.number,
                        title: $pr.title,
                        url: $pr.url,
                        mergedAt: $pr.mergedAt,
                        labels: $pr.labels.nodes
                    }
                }),
                # Merge commit (if exists)
                (if $pr.mergeCommit and $pr.mergeCommit.oid then {
                    commit: $pr.mergeCommit.oid,
                    pr: {
                        number: $pr.number,
                        title: $pr.title,
                        url: $pr.url,
                        mergedAt: $pr.mergedAt,
                        labels: $pr.labels.nodes
                    }
                } else empty end)
            )
        ] |
        group_by(.commit) |
        map({key: .[0].commit, value: .[0].pr}) |
        from_entries
    ')

    # Match commits to PRs (use temp files to avoid argument length limits)
    local temp_commits_file=$(mktemp)
    local temp_map_file=$(mktemp)
    echo "$commits_json" > "$temp_commits_file"
    echo "$commit_to_pr_map" > "$temp_map_file"

    local result=$(jq --slurpfile map "$temp_map_file" '
        map(. as $commit | if $map[0][$commit] then {commit: $commit, pr: $map[0][$commit]} else {commit: $commit, pr: null} end)
    ' "$temp_commits_file")

    rm "$temp_commits_file" "$temp_map_file"
    echo "$result"
}

# Function to add ticket data to the parsed JSON
add_to_parsed_tickets_json() {
    local commit_title="$1"
    local pr_url_input="$2"

    # Extract first Jira key from the title message
    local ticket="$(grep -oE '([A-Z]+-[0-9]+)' <<<"$commit_title" | head -n1 || true)"
    if [[ -z "$ticket" ]]; then
        echo "No ticket found in the commit title, skipping..."
        return
    fi

    # Validate PR URL if provided
    local pr_url=""
    if [[ "$pr_url_input" =~ ^https?:// ]]; then
        pr_url="$pr_url_input"
    fi

    # Append the ticket and PR URL (if present) to the parsed JSON
    PARSED_TICKETS_JSON="$(jq --arg ticket "$ticket" --arg pr_url "$pr_url" \
        '. += [ {"ticket": $ticket} + (if $pr_url != "" then {"pr_url": $pr_url} else {} end) ]' \
        <<<"$PARSED_TICKETS_JSON")"
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

# Clone the repository
tmpDir=$(mktemp -d)
releaseServiceCatalogDir=${tmpDir}/release-service-catalog
mkdir -p ${releaseServiceCatalogDir}

echo -e "---\nPromoting release-service-catalog ${SOURCE_BRANCH} to ${TARGET_BRANCH}\n---\n"

git clone "https://oauth2:$token@github.com/$ORG/$REPO.git" "${releaseServiceCatalogDir}"
cd "${releaseServiceCatalogDir}"

# A change cannot go into production if the changes in staging are less than six days old
if [[ "${TARGET_BRANCH}" == "production" && "${OVERRIDE}" != "true" ]] ; then
    git checkout origin/staging
    check_if_any_commits_in_last_six_days
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
    exit 0
fi

# Calculate oldest date based on constant days back from current date
OLDEST_DATE=$(date --date="$COMMIT_MAX_AGE_DAYS days ago" +%Y-%m-%d)

echo "Fetching PRs from the last $COMMIT_MAX_AGE_DAYS days (since $OLDEST_DATE)"

# Fetch PRs since the calculated date using GraphQL
ALL_PRS=$(get_all_prs_since_date "$OLDEST_DATE")

total_prs=$(echo "$ALL_PRS" | jq 'length')
echo "Found $total_prs PRs since $OLDEST_DATE"

# Convert commits array to JSON for processing
COMMITS_JSON=$(printf '%s\n' "${COMMITS[@]}" | jq -R . | jq -s .)

echo "Analyzing ${#COMMITS[@]} commits from development branch for PR matching..."

# Find matching PRs for our commits
MATCHED_RESULTS=$(find_prs_for_commits "$COMMITS_JSON" "$ALL_PRS")

# Count relevant PRs (those with commits in development branch)
relevant_prs=$(echo "$MATCHED_RESULTS" | jq -r '[.[] | select(.pr != null) | .pr.number] | unique | length')
echo ""
echo "📊 PR Analysis Summary:"
echo "======================"
echo "Total PRs found in $COMMIT_MAX_AGE_DAYS-day window: $total_prs"
echo "Relevant PRs for promotion: $relevant_prs"
echo "Commits to promote: ${#COMMITS[@]}"
echo ""

# Display results in the requested format: PR link above each commit message
echo "Included PRs:"
for COMMIT in "${COMMITS[@]}"; do
    # Get PR info for this commit
    COMMIT_PR_INFO=$(echo "$MATCHED_RESULTS" | jq -r --arg commit "$COMMIT" '
        .[] | select(.commit == $commit) |
        if .pr then
            .pr.url
        else
            null
        end
    ')

    # If no PR found via GraphQL, fall back to GitHub Search API (like original script)
    if [ "$COMMIT_PR_INFO" = "null" ] || [ -z "$COMMIT_PR_INFO" ]; then
        COMMIT_PR_INFO=$(curl -s -H 'Authorization: token '"$token" 'https://api.github.com/search/issues?q=sha:'"$COMMIT" | jq -r '.items[]
            | select(.repository_url=="https://api.github.com/repos/'"$ORG"'/'"$REPO"'")
            | .pull_request | select(.merged_at!=null) | .html_url' || true)
    fi

    # Show PR URL if found
    if [ "$COMMIT_PR_INFO" != "null" ] && [ -n "$COMMIT_PR_INFO" ]; then
        echo "$COMMIT_PR_INFO"
    fi

    # Show commit message
    commit_title=$(git show --oneline --no-patch --no-decorate "$COMMIT") || {
        echo "Error: Failed to get commit message for $COMMIT"
        exit 1
    }
    echo "$commit_title"

    # Adds each ticket to the parsed JSON
    add_to_parsed_tickets_json "$commit_title" "$COMMIT_PR_INFO"
done

# Check if there are any breaking changes
BREAKING_COUNT=$(echo "$MATCHED_RESULTS" | jq -r '
    [.[] | select(.pr and (.pr.labels | map(select(.name | test("breaking[-_ ]change|breaking"; "i"))) | length > 0))] | length
')

# Only show breaking change summary if there are breaking changes
if [ "$BREAKING_COUNT" -gt 0 ]; then
    echo -e "\n📢 NOTICE: Promoting $BREAKING_COUNT breaking change(s) to $TARGET_BRANCH!"
    BREAKING_CHANGES=$(echo "$MATCHED_RESULTS" | jq -r '
        [.[] | select(.pr and (.pr.labels | map(select(.name | test("breaking[-_ ]change|breaking"; "i"))) | length > 0))] |
        "⚠️  Found \(length) PR(s) with breaking changes:\n" +
        (map("  - PR #\(.pr.number): \(.pr.title) (\(.pr.labels | map(select(.name | test("breaking[-_ ]change|breaking"; "i"))) | map(.name) | join(", ")))") | join("\n"))
    ')
    echo "$BREAKING_CHANGES"
fi

PARSED_TICKETS_FILE=$(mktemp)
echo "Parsed tickets JSON for Jira promotion:"
tee "$PARSED_TICKETS_FILE" <<< "$PARSED_TICKETS_JSON"
echo "parsed_tickets_file=$PARSED_TICKETS_FILE" >> "$GITHUB_OUTPUT"

if [ "${DRY_RUN}" == "true" ] ; then
    exit
fi

git checkout "$SOURCE_BRANCH"
git push origin "$SOURCE_BRANCH:$TARGET_BRANCH"

cd -
rm -rf ${tmpDir}
