#!/usr/bin/env bash

# This script applies a hot fix from a specific PR to staging and production branches.
#
# The script takes a PR number that must be merged into the development branch,
# finds the commit that was merged, and attempts to apply it to both staging
# and production branches. If the commit applies cleanly, it creates a new PR
# for each target branch.
#
# This script was created with help by Cursor
#
# Prerequisites:
#   - An environment variable GITHUB_TOKEN is defined that provides access to the user's account
#   - curl, git and jq installed
#   - The PR must be merged into the development branch
#
# Environment Variables:
#   GITHUB_TOKEN    - Required. GitHub token with repo access

set -e

# GitHub repository details
ORG="konflux-ci"
REPO="release-service-catalog"

# Personal access token with appropriate permissions
token="${GITHUB_TOKEN}"

print_help(){
    echo "Usage: $0 --pr-number PR_NUMBER [--target-branches TARGET] [--dry-run false]"
    echo
    echo "  --pr-number:       The PR number to hot fix (must be merged into development branch)"
    echo "  --target-branches: Which branches to target (both, staging, production). Default: both"
    echo "  --dry-run:         If passed with value true, print out the changes that would"
    echo "                     be made but do not create PRs"
    echo
    echo "  --pr-number has to be specified."
}

OPTIONS=$(getopt --long "pr-number:,dry-run:,comment-trigger:,target-branches:,help" -o "p:,h" -- "$@")
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -p|--pr-number)
            PR_NUMBER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        --comment-trigger)
            IS_COMMENT_TRIGGER="$2"
            shift 2
            ;;
        --target-branches)
            TARGET_BRANCHES="$2"
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

# Validate required parameters
if [ -z "${PR_NUMBER}" ]; then
    echo -e "Error: missing required parameter --pr-number\n"
    print_help
    exit 1
fi

if [ -z "${GITHUB_TOKEN}" ]; then
    echo -e "Error: missing 'GITHUB_TOKEN' environment variable\n"
    print_help
    exit 1
fi

# Set default value for TARGET_BRANCHES if not provided
if [ -z "${TARGET_BRANCHES}" ]; then
    TARGET_BRANCHES="both"
fi

# Function to make GitHub API calls
github_api() {
    endpoint="$1"
    method="${2:-GET}"
    data="${3:-}"
    
    if [ -n "$data" ]; then
        curl -s -H "Authorization: token $token" \
             -H "Accept: application/vnd.github.v3+json" \
             -X "$method" \
             -d "$data" \
             "https://api.github.com/repos/$ORG/$REPO/$endpoint"
    else
        curl -s -H "Authorization: token $token" \
             -H "Accept: application/vnd.github.v3+json" \
             -X "$method" \
             "https://api.github.com/repos/$ORG/$REPO/$endpoint"
    fi
}

# Function to comment on a PR
comment_on_pr() {
    pr_number="$1"
    comment_body="$2"
    
    comment_data=$(jq -n --arg body "$comment_body" '{body: $body}')
    echo "Adding comment to PR #$pr_number..."
    github_api "issues/$pr_number/comments" "POST" "$comment_data" > /dev/null
}

# Function to exit with error and optional PR comment
exit_with_error() {
    error_message="$1"
    exit_code="${2:-1}"
    
    echo "$error_message"
    
    if [ "${IS_COMMENT_TRIGGER}" = "true" ]; then
        comment_on_pr "$PR_NUMBER" "$error_message"
    fi
    
    exit "$exit_code"
}

# Function to create a PR
create_pr() {
    source_branch="$1"
    target_branch="$2"
    title="$3"
    body="$4"
    
    pr_data=$(cat <<EOF
{
    "title": "$title",
    "body": "$body",
    "head": "$source_branch",
    "base": "$target_branch"
}
EOF
)
    
    echo "Creating PR from $source_branch to $target_branch..."
    if [ "${DRY_RUN}" != "true" ]; then
        result=$(github_api "pulls" "POST" "$pr_data")
        pr_url=$(jq -r '.html_url // empty' <<< "$result")
        
        if [ -n "$pr_url" ]; then
            echo "Created PR: $pr_url"
            # Set global variables
            if [ "$target_branch" = "staging" ]; then
                STAGING_PR_URL="$pr_url"
            elif [ "$target_branch" = "production" ]; then
                PRODUCTION_PR_URL="$pr_url"
            fi
            echo "$pr_url"  # Return the URL
        else
            echo "Failed to create PR"
            echo jq -r '.message // "Unknown error"' <<< "$result"
            return 1
        fi
    fi
}

echo "Fetching PR #$PR_NUMBER information..."

# Get PR information
PR_INFO=$(github_api "pulls/$PR_NUMBER")

# Check if PR exists
# Note: GitHub API returns a .message field only when there's an ERROR (e.g. PR not found)
# Successful responses contain PR data without a .message field
api_error_message=$(jq -r '.message // empty' <<< "$PR_INFO")
if [ -n "$api_error_message" ]; then
    exit_with_error "Error: PR #$PR_NUMBER - $api_error_message"
fi

# Check if PR is merged
IS_MERGED=$(jq -r '.merged' <<< "$PR_INFO")
if [ "$IS_MERGED" != "true" ]; then
    exit_with_error "Error: PR #$PR_NUMBER is not merged"
fi

# Check if PR was merged into development branch
BASE_BRANCH=$(jq -r '.base.ref' <<< "$PR_INFO")
if [ "$BASE_BRANCH" != "development" ]; then
    exit_with_error "Error: PR #$PR_NUMBER was merged into '$BASE_BRANCH', not 'development'"
fi

# Get merge commit SHA
MERGE_COMMIT=$(jq -r '.merge_commit_sha' <<< "$PR_INFO")
if [ -z "$MERGE_COMMIT" ] || [ "$MERGE_COMMIT" = "null" ]; then
    exit_with_error "Error: Could not find merge commit for PR #$PR_NUMBER"
fi

# Get PR title for the new commit
PR_TITLE=$(jq -r '.title' <<< "$PR_INFO")

echo "   Found PR #$PR_NUMBER:"
echo "   Title: $PR_TITLE"
echo "   Merged into: $BASE_BRANCH"
echo "   Merge commit: $MERGE_COMMIT"

# Clone the repository
tmpDir=$(mktemp -d)
repoDir=${tmpDir}/release-service-catalog
mkdir -p ${repoDir}

echo -e "\n---\nCloning repository and preparing branches\n---\n"

git clone "https://oauth2:$token@github.com/$ORG/$REPO.git" "${repoDir}"
cd "${repoDir}"

# Configure git user
git config user.name "Konflux-Release-Team"
git config user.email "konflux-release-team@redhat.com"

# Function to apply commit to a branch and create PR
apply_to_branch() {
    target_branch="$1"
    # Generate 5 character random string for unique branch names
    random_suffix=$(uuidgen | head -c 5)
    hotfix_branch="hotfix/pr-${PR_NUMBER}-to-${target_branch}-${random_suffix}"
    
    echo "Processing branch: $target_branch"
    
    # Checkout target branch
    git checkout "origin/$target_branch"
    
    # Create hotfix branch
    git checkout -b "$hotfix_branch"

    # Try to cherry-pick the commit
    echo "Attempting to cherry-pick commit $MERGE_COMMIT onto $target_branch..."

    # Dynamically set cherry-pick options based on commit type
    PARENT_COUNT=$(git show --format="%P" -s "$MERGE_COMMIT" | wc -w)
    if [ "$PARENT_COUNT" -gt 1 ]; then
        CHERRY_PICK_OPTS="--no-edit -m 1"
    else
        CHERRY_PICK_OPTS="--no-edit"
    fi
    
    if git cherry-pick "$MERGE_COMMIT" $CHERRY_PICK_OPTS; then
        echo "Commit applies cleanly to $target_branch"
        
        # Update commit message
        git commit --amend -m "$PR_TITLE" -m "Hot fix of PR #${PR_NUMBER} to $target_branch"
        
        if [ "${DRY_RUN}" != "true" ]; then
            # Push the branch
            git push origin "$hotfix_branch"
            
            # Create PR
            create_pr "$hotfix_branch" "$target_branch" "$PR_TITLE" "Hot fix of PR #${PR_NUMBER} to $target_branch"
        else
            echo "[DRY RUN] Would push branch $hotfix_branch and create PR to $target_branch with title $PR_TITLE and body Hot fix of PR #${PR_NUMBER} to $target_branch"
        fi
    else
        echo "Error: Commit does not apply cleanly to $target_branch"
        echo "Conflicts detected. Manual intervention required."
        git cherry-pick --abort
        exit_with_error "Error: Commit does not apply cleanly to $target_branch. Conflicts detected. Manual intervention required."
    fi
    
    # Switch back to development for next iteration
    git checkout development
}

# Apply to branches based on target selection
if [ "$TARGET_BRANCHES" = "both" ] || [ "$TARGET_BRANCHES" = "staging" ]; then
    apply_to_branch "staging"
fi

if [ "$TARGET_BRANCHES" = "both" ] || [ "$TARGET_BRANCHES" = "production" ]; then
    apply_to_branch "production"
fi

# Cleanup
cd -
if [ "${DRY_RUN}" != "true" ]; then
    rm -rf ${tmpDir}
else
    echo "[DRY RUN] Temporary directory preserved at: $tmpDir"
fi

echo -e "\nHot fix process completed successfully!"

# Add success comment on PR (unless dry run)
if [ "${DRY_RUN}" != "true" ]; then
    if [ "$TARGET_BRANCHES" = "both" ]; then
        comment_body="Hot fix process completed successfully! PRs have been created for both staging and production branches.

**Created PRs:**
- **Staging**: $STAGING_PR_URL
- **Production**: $PRODUCTION_PR_URL"
    elif [ "$TARGET_BRANCHES" = "staging" ]; then
        comment_body="Hot fix process completed successfully! PR has been created for the staging branch.

**Created PR:**
- **Staging**: $STAGING_PR_URL"
    elif [ "$TARGET_BRANCHES" = "production" ]; then
        comment_body="Hot fix process completed successfully! PR has been created for the production branch.

**Created PR:**
- **Production**: $PRODUCTION_PR_URL"
    fi
    
    comment_on_pr "$PR_NUMBER" "$comment_body"
fi
