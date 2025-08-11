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
#   - If there are hotfix commits in TARGET_BRANCH which are not in SOURCE_BRANCH,
#     the script will fail unless --force-hotfix is set. This will collect the hotfixes and apply them to SOURCE_BRANCH.
#     Then the script will push SOURCE_BRANCH to TARGET_BRANCH forcefully.
#
# Prerequisites:
#   - An environment variable GITHUB_TOKEN is defined that provides access to the user's account. See
#     https://github.com/konflux-ci/release-service-utils/blob/main/ci/promote-overlay/README.md#setup for help.
#   - curl, git and jq installed.

set -e

# GitHub repository details
ORG="konflux-ci"
REPO="release-service-catalog"

# Git Committer Configuration
git config --global user.email "konflux-release-team@redhat.com"
git config --global user.name "Konflux Release Team"

# --Color codes--
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OPTIONS=$(getopt --long "promotion-type:,force-to-staging:,override:,dry-run:,force-hotfix:,help" -o "p:,h" -- "$@")
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
        --force-hotfix)
            FORCE_HOTFIX="$2"
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
    esac
done

print_help(){
    echo "Usage: $0 --promotion-type branch1-to-branch2 [--force-to-staging false] [--override false] [--dry-run false] [--force-hotfix false]"
    echo
    echo "  --promotion-type:   The type of promotion to perform. Either development-to-staging"
    echo "                      or staging-to-production."
    echo "  --force-to-staging: If passed with value true, allow promotion to staging even"
    echo "                      if staging and production differ."
    echo "  --override:         If passed with value true, allow promotion to production"
    echo "                      even if the change has not been in staging for one week."
    echo "  --force-hotfix:     If passed with value true, add the hotfixes identified from target branch"
    echo "                      to the source branch and forcefully promote the code to target branch"
    echo "  --dry-run:          If passed with value true, print out the changes that would"
    echo "                      be promoted but do not git push or delete the temp repo."
    echo
    echo "  --promotion-type has to be specified."
}

# Print functions to print in different colors
print_error() {
    echo -e "${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

check_if_branch_differs() {
    ACTUAL_DIFFERENT_LINES=$(git diff --numstat origin/"$1" | wc -l) 
    if [ "$ACTUAL_DIFFERENT_LINES" -ne 0 ] ; then
        print_error "Lines differ in branch $1,Production and stage branches are not in sync"
        print_info "Actual differing lines: \n "
        echo -e "$(git diff --numstat origin/"$1")"
        exit 1
    fi
}

check_if_any_commits_in_last_week() {
    NEW_COMMITS=$(git log --oneline --since="$(date --date="6 days ago" +%Y-%m-%d)" | wc -l)
    if [ "$NEW_COMMITS" -ne 0 ] ; then
        print_error "There are commits in staging that are less than a week old. Blocking promotion to production"
        print_info "Commits less than a week old: \n "
        echo -e "$(git log --oneline --since="$(date --date="6 days ago" +%Y-%m-%d)")"
        exit 1
    fi
}

# Collect all hotfix commits of TARGET_BRANCH that are not present in SOURCE_BRANCH
# Note: git rev-list matches commits by patchID, not hash (identical content = duplicates)
collect_hotfixes_in_target_branch() {
    mapfile -t HOTFIX_COMMITS < <(git rev-list --reverse --no-merges --cherry-pick --right-only origin/${SOURCE_BRANCH}..origin/${TARGET_BRANCH})
    if [ ${#HOTFIX_COMMITS[@]} -eq 0 ]; then
        print_info "No hotfixes detected in ${TARGET_BRANCH} that are not in ${SOURCE_BRANCH}.\n"
    else
        print_info "Detected hotfix commits in ${TARGET_BRANCH} not present in ${SOURCE_BRANCH}.\n"
        for commit in "${HOTFIX_COMMITS[@]}"; do
            git show --no-patch "$commit"
        done
        # Export the list for use
        export HOTFIX_COMMITS
    fi
}

# Add all the hotfixes collected in HOTFIX_COMMITS to the source branch
# if patch content is already present in source branch, skip the commit
add_hotfixes_to_source_branch() {
    git checkout $SOURCE_BRANCH
    for commit in "${HOTFIX_COMMITS[@]}"; do
        print_info "Cherry-picking hotfix commit $commit onto ${SOURCE_BRANCH}..."
        set +e
        cherry_pick_output=$(git cherry-pick -x "$commit" 2>&1) 
        set -e
        cherry_pick_status=$?
        if [ $cherry_pick_status -ne 0 ]; then
            if echo "$cherry_pick_output" | grep -q "nothing to commit"; then
                print_info "Patch already present - skipping commit $commit \n"
                git cherry-pick --skip
            else
                print_error "$cherry_pick_output"
                print_error "Conflict occurred while cherry-picking $commit. Please resolve conflicts and continue.\n"
                git show "$commit"
                git cherry-pick --abort
                exit 1
            fi
        fi
    done
    # If no conflicts with all commits, push the commits to the source branch
    git push origin $SOURCE_BRANCH
    
    print_success "All hotfixes have been applied to ${SOURCE_BRANCH}.\n"
}

if [ -z "${PROMOTION_TYPE}" ]; then
    print_error "Error: missing '--promotion-type' argument"
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
    print_error "Invalid promotion type. Only 'development-to-staging' and 'staging-to-production' are allowed"
    print_help
    exit 1
fi
if [ -z "${GITHUB_TOKEN}" ]; then
    print_error "Error: missing 'GITHUB_TOKEN' environment variable"
    print_help
    exit 1
fi

# Personal access token with appropriate permissions
token="${GITHUB_TOKEN}"

# Clone the repository
tmpDir=$(mktemp -d)
releaseServiceCatalogDir=${tmpDir}/release-service-catalog
mkdir -p "${releaseServiceCatalogDir}"

print_info "Promoting release-service-catalog ${SOURCE_BRANCH} to ${TARGET_BRANCH}...\n"

git clone "https://oauth2:$GITHUB_TOKEN@github.com/$ORG/$REPO.git" "${releaseServiceCatalogDir}"
cd "${releaseServiceCatalogDir}" || exit 1

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

print_info "Included PRs:\n"
mapfile -t COMMITS < <(git rev-list --first-parent --ancestry-path origin/"$TARGET_BRANCH"'...'origin/"$SOURCE_BRANCH")
## now loop through the above array
for COMMIT in "${COMMITS[@]}"; do
  curl -s   -H 'Authorization: token  '"$token"  'https://api.github.com/search/issues?q=sha:'"$COMMIT" | jq -r '.items[]
    | select(.repository_url=="https://api.github.com/repos/'"$ORG"'/'"$REPO"'")
    | .pull_request | select(.merged_at!=null) | .html_url'
  git show --oneline --no-patch "$COMMIT"
done

if [ "${DRY_RUN}" == "true" ] ; then
    if [[ "${FORCE_HOTFIX}" == "true" ]]; then
        collect_hotfixes_in_target_branch
    fi
    exit
fi

collect_hotfixes_in_target_branch
if [[ "${FORCE_HOTFIX}" == "true" ]] && [ "${#HOTFIX_COMMITS[@]}" -ne 0 ]; then
    add_hotfixes_to_source_branch
    git push --force origin $SOURCE_BRANCH:$TARGET_BRANCH
    exit 0
fi

# Push the source branch to the target branch
git checkout $SOURCE_BRANCH
git push origin $SOURCE_BRANCH:$TARGET_BRANCH
