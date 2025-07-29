#!/bin/bash
#
# validate-pac-repository.sh - Validates PAC Repository CRs and their dependencies
#
# This script searches for Repository CRs with a specific URL in a given namespace
# and validates that:
#   1. The referenced git provider secret exists and contains expected keys
#   2. All Component ownerReferences point to existing Components
#
# Why do we need this?
#
# When a Component is onboarded, it creates a Repository CR that points to the Component's git repository.
# The Repository CR is used to fetch the Component's source code and metadata.
#
# However, if the Repository CR is not properly pruned, it may cause a Component onboarding to fail if the
# Repository points to a secret that does not exist.
#
# Since multiple tests may run in parallel and since Pipelines-as-code attempts to re-use Repositories for
# a given Github Url, we need to validate that the Repository CRs have the correct
# referenced secrets and Components.
#
# Environment Variables:
#   TARGET_URL  - The repository URL to search for (required)
#   NAMESPACE   - The Kubernetes namespace to search in (required)
#
# Exit Codes:
#   0 - All validations passed
#   1 - One or more validation errors found
#

set -euo pipefail

# Check required environment variables
if [[ -z "${TARGET_URL:-}" ]]; then
    echo "Error: TARGET_URL environment variable is required"
    echo "Usage: TARGET_URL='https://github.com/owner/repo' NAMESPACE='namespace' $0"
    exit 1
fi

if [[ -z "${NAMESPACE:-}" ]]; then
    echo "Error: NAMESPACE environment variable is required"
    echo "Usage: TARGET_URL='https://github.com/owner/repo' NAMESPACE='namespace' $0"
    exit 1
fi

echo "Searching for Repository CRs with URL: ${TARGET_URL} in namespace: ${NAMESPACE}"
echo "Will validate secrets and Component ownerReferences..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed or not in PATH"
    exit 1
fi

# Check if the namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Error: Namespace '${NAMESPACE}' does not exist"
    exit 1
fi

# Find Repository CRs with the target URL in the specified namespace
repositories=$(kubectl get repositories -n "$NAMESPACE" -o json | jq -r --arg url "$TARGET_URL" '
    .items[] | 
    select(.spec.url == $url) | 
    "\(.metadata.name)|\(.spec.git_provider.secret.name // "none")|\(.metadata.ownerReferences // [] | map(select(.kind == "Component") | .name) | join(","))"
')

if [[ -z "$repositories" ]]; then
    echo "No Repository CRs found with URL: ${TARGET_URL} in namespace: ${NAMESPACE}"
    exit 0
fi

echo ""
echo "Found Repository CRs:"

# Track validation failures
validation_failed=false

# Process each found repository
while IFS='|' read -r repo_name secret_name component_names; do
    if [[ -z "$repo_name" ]]; then
        continue
    fi
    
    echo "• Repository: ${repo_name}"
    echo "  Secret: ${secret_name}"
    if [[ -n "$component_names" ]]; then
        echo "  Referenced Components: ${component_names}"
    else
        echo "  Referenced Components: none"
    fi
    
    # Validate that the secret exists
    if [[ "$secret_name" == "none" || -z "$secret_name" ]]; then
        echo "  ❌ ERROR: No secret name specified in git_provider.secret.name"
        validation_failed=true
        continue
    fi
    
    echo "  🔍 Checking if secret '${secret_name}' exists in namespace '${NAMESPACE}'..."
    
    if kubectl get secret "$secret_name" -n "$NAMESPACE" &>/dev/null; then
        echo "  ✅ SUCCESS: Secret '${secret_name}' exists in namespace '${NAMESPACE}'"
        
        # Optional: Check if the secret has the expected key
        secret_keys=$(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "")
        if [[ -n "$secret_keys" ]]; then
            echo "  📋 Secret keys: $(echo "$secret_keys" | tr '\n' ' ')"
            
            # Check for common git provider secret keys
            if echo "$secret_keys" | grep -q "password"; then
                echo "  ✅ Secret contains 'password' key as expected"
            else
                echo "  ⚠️  WARNING: Secret does not contain 'password' key"
                # Note: Not setting validation_failed=true for missing password key as it's just a warning
            fi
        fi
    else
        echo "  ❌ ERROR: Secret '${secret_name}' does not exist in namespace '${NAMESPACE}'"
        echo ""
        echo "     Note: This may cause a Component onboarding to fail if a Repository points to a secret that does not exist."
        echo "           To fix, delete the Repository CR and re-run the test."
        validation_failed=true
    fi
    
    # Validate that referenced Components exist
    if [[ -n "$component_names" ]]; then
        echo "  🔍 Checking if referenced Components exist in namespace '${NAMESPACE}'..."
        IFS=',' read -ra COMPONENTS <<< "$component_names"
        for component_name in "${COMPONENTS[@]}"; do
            # Skip empty component names
            if [[ -z "$component_name" ]]; then
                continue
            fi
            
            echo "    🔍 Checking Component: ${component_name}"
            if kubectl get component "$component_name" -n "$NAMESPACE" &>/dev/null; then
                echo "    ✅ SUCCESS: Component '${component_name}' exists in namespace '${NAMESPACE}'"
            else
                echo "    ❌ ERROR: Component '${component_name}' does not exist in namespace '${NAMESPACE}'"
                echo ""
                echo "       Note: This may cause a Component onboarding to fail if Repositories are not properly pruned."
                echo "             To fix, update the ownerReferences of the Repository CR to remove the Component."
                validation_failed=true
            fi
        done
    else
        echo "  ⚠️  WARNING: No Component ownerReferences found for this Repository"
    fi
    
    echo ""
done <<< "$repositories"

# Exit with appropriate code based on validation results
if [[ "$validation_failed" == "true" ]]; then
    echo "Validation complete with errors - some secrets or Components are missing."
    exit 1
else
    echo "Validation complete - all secrets and Components exist as expected."
    exit 0
fi 
