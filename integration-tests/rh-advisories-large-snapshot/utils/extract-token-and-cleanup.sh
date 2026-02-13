#!/usr/bin/env bash
set -euo pipefail

# Extract GitHub token from vault and run full cleanup
# This script will prompt for the vault password

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Extracting GitHub Token and Running Full Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if vault file exists
if [ ! -f "vault/tenant-secrets.yaml" ]; then
    echo "❌ Error: vault/tenant-secrets.yaml not found"
    exit 1
fi

# Extract token from vault (will prompt for password)
echo "📦 Extracting GitHub token from vault..."
echo "   (You will be prompted for the vault password)"
echo ""

VAULT_OUTPUT=$(ansible-vault view vault/tenant-secrets.yaml 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Failed to decrypt vault file"
    echo ""
    echo "Alternative: Extract token from Kubernetes secret:"
    echo "  export GITHUB_TOKEN=\$(kubectl get secret hacbs-release-tests-token \\"
    echo "    -n dev-release-team-tenant -o jsonpath='{.data.token}' | base64 -d)"
    echo ""
    echo "Then run: ./utils/cleanup-all.sh"
    exit 1
fi

# Extract token using yq or grep
# The vault contains a secret template with the token in stringData.password
if command -v yq &> /dev/null; then
    GITHUB_TOKEN=$(echo "$VAULT_OUTPUT" | yq -r '.stringData.password // .data.password // empty')
else
    # Fallback: grep for password field
    GITHUB_TOKEN=$(echo "$VAULT_OUTPUT" | grep "password:" | awk '{print $2}' | tr -d '"' || echo "")
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Failed to extract token from vault"
    echo ""
    echo "Vault structure:"
    echo "$VAULT_OUTPUT" | head -50
    exit 1
fi

export GITHUB_TOKEN

echo "✅ Token extracted successfully"
echo "   Token starts with: ${GITHUB_TOKEN:0:10}..."
echo "   Token length: ${#GITHUB_TOKEN} characters"
echo ""

# Run cleanup
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Starting Full Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exec "$SCRIPT_DIR/cleanup-all.sh"
