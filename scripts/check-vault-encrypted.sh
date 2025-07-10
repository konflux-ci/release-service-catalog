#!/bin/bash

# check-vault-encrypted.sh - Pre-commit hook to ensure vault files are encrypted
# This script checks that files matching vault patterns are encrypted with Ansible Vault

set -e

# Function to check if a file is encrypted
is_vault_encrypted() {
    local file="$1"

    # Check if file exists and is readable
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        echo "ERROR: Cannot read file: $file"
        return 1
    fi

    # Check if file starts with Ansible Vault header
    if head -n 1 "$file" | grep -q '^\$ANSIBLE_VAULT;'; then
        return 0  # File is encrypted
    else
        return 1  # File is not encrypted
    fi
}

# Main execution
exit_code=0
unencrypted_files=()

# Check each file passed as argument
for file in "$@"; do
    if [[ -f "$file" ]]; then
        if ! is_vault_encrypted "$file"; then
            unencrypted_files+=("$file")
            exit_code=1
        fi
    fi
done

# Report results
if [[ ${#unencrypted_files[@]} -gt 0 ]]; then
    echo "❌ ERROR: The following vault files are not encrypted:"
    for file in "${unencrypted_files[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "To encrypt these files, use:"
    echo "  ansible-vault encrypt <file>"
    echo ""
    echo "Or if you have a vault password file:"
    echo "  ansible-vault encrypt --vault-password-file <password-file> <file>"
    echo ""
    echo "Commit aborted to prevent committing unencrypted secrets."
else
    echo "✅ All vault files are properly encrypted."
fi

exit $exit_code
