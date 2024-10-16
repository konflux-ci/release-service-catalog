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

OPTIONS=$(getopt --long "target-branch:,force-to-staging:,override:,dry-run:,help" -o "tgt:,h" -- "$@")
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -tgt|--target-branch)
            TARGET_BRANCH="$2"
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
    echo "Usage: $0 --target-branch branch [--force-to-staging false] [--override false] [--dry-run false]"
    echo
    echo "  --target-branch:    The name of the branch to be promoted. Options are staging"
    echo "                      and production."
    echo "  --force-to-staging: If passed with value true, allow promotion to staging even"
    echo "                      if staging and production differ."
    echo "  --override:         If passed with value true, allow promotion to production"
    echo "                      even if the change has not been in staging for one week."
    echo "  --dry-run:          If passed with value true, print out the changes that would"
    echo "                      be promoted but do not git push or delete the temp repo."
    echo
    echo "  --target-branch has to be specified."
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

if [ -z "${TARGET_BRANCH}" ]; then
    echo -e "Error: missing 'target-branch' argument\n"
    print_help
    exit 1
fi
if [ "${TARGET_BRANCH}" == "staging" ]; then
    SOURCE_BRANCH="development"
    # App sre restricts what branches we can consume from, so we create duplicate branches internal and stable
    # to fit their regex requirements
    SRE_DUPLICATE_BRANCH="internal"
elif [ "${TARGET_BRANCH}" == "production" ]; then
    SOURCE_BRANCH="staging"
    SRE_DUPLICATE_BRANCH="stable"
else
    echo "Invalid target-branch. Only 'staging' and 'production' are allowed"
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
COMMITS=($(git rev-list --first-parent --ancestry-path origin/"$TARGET_BRANCH"'...'origin/"$SOURCE_BRANCH"))
## now loop through the above array
for COMMIT in "${COMMITS[@]}"
do
  echo $(curl -s   -H 'Authorization: token  '"$token"  'https://api.github.com/search/issues?q=sha:'"$COMMIT" | jq -r '.items[]
    | select(.repository_url=="https://api.github.com/repos/'"$ORG"'/'"$REPO"'")
    | .pull_request | select(.merged_at!=null) | .html_url')
  git show --oneline --no-patch $COMMIT
done

if [ "${DRY_RUN}" == "true" ] ; then
    exit
fi

git checkout $SOURCE_BRANCH
git push origin $SOURCE_BRANCH:$TARGET_BRANCH
git push origin $SOURCE_BRANCH:$SRE_DUPLICATE_BRANCH

cd -
rm -rf ${tmpDir}
