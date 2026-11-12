#!/bin/bash
set -euo pipefail

pushd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null
SCRIPT_DIR="$(pwd)"
popd >/dev/null
pushd "${SCRIPT_DIR}/.." >/dev/null
REPO_ROOT="$(pwd)"
popd >/dev/null

VAULT_PASSWORD_FILE="${VAULT_PASSWORD_FILE:-}"
TEMP_PASS_FILE=""
TEMP_DECRYPTED_FILE=""
TEMP_ENCRYPTED_FILE=""
VAULT_DISCOVERY_FILE=""
TARGET_VARS=(
    "AWS_ACCESS_KEY_ID" "AWS_DEFAULT_REGION" "AWS_SECRET_ACCESS_KEY" "PUBLIC_KEY"
    "REKOR_PUBLIC_KEY" "REKOR_URL" "SIGN_KEY" "USERNAME"
)

cleanup() {
    rm -f "${TEMP_PASS_FILE}" "${TEMP_DECRYPTED_FILE}" "${TEMP_ENCRYPTED_FILE}" "${VAULT_DISCOVERY_FILE}"
}
trap cleanup EXIT

show_help() {
    cat << EOF
Usage: ${0} [OPTIONS] [VAULT_PASSWORD_FILE]

Iterates over all vault files under integration-tests/, decrypts them using ansible-vault,
updates target variables (AWS_ACCESS_KEY_ID, AWS_DEFAULT_REGION, AWS_SECRET_ACCESS_KEY,
PUBLIC_KEY, REKOR_PUBLIC_KEY, REKOR_URL, SIGN_KEY, USERNAME) with base64 encoded
values read from their corresponding <VARIABLE>_FILE paths, and re-encrypts updated files.

Options:
  --vault-password-file FILE  Path to Ansible Vault password file
  --ask-vault-password        Prompt interactively for Ansible Vault password
  -h, --help                  Show this help message

Examples:
  AWS_ACCESS_KEY_ID_FILE=/mnt/secrets/aws-access-key-id ${0} /path/to/vaultpass
  SIGN_KEY_FILE=/mnt/secrets/sign-key ${0} --vault-password-file /path/to/vaultpass
  REKOR_URL_FILE=/mnt/secrets/rekor-url ${0} --ask-vault-password
EOF
}

ASK_VAULT_PASS=false

while [[ ${#} -gt 0 ]]; do
    case "${1}" in
        --vault-password-file)
            if [[ ${#} -lt 2 ]]; then
                echo "Error: --vault-password-file requires a file path." >&2
                exit 1
            fi
            VAULT_PASSWORD_FILE="${2}"
            shift 2
            ;;
        --ask-vault-password|--ask-vault-pass)
            ASK_VAULT_PASS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "${VAULT_PASSWORD_FILE}" && "${1}" != -* ]]; then
                VAULT_PASSWORD_FILE="${1}"
                shift
            else
                echo "Error: Unknown argument '${1}'" >&2
                show_help
                exit 1
            fi
            ;;
    esac
done

if [[ "${ASK_VAULT_PASS}" == "true" ]]; then
    read -r -s -p "Vault password: " vault_password
    echo ""
    TEMP_PASS_FILE="$(mktemp)"
    chmod 600 "${TEMP_PASS_FILE}"
    echo -n "${vault_password}" > "${TEMP_PASS_FILE}"
    VAULT_PASSWORD_FILE="${TEMP_PASS_FILE}"
elif [[ -z "${VAULT_PASSWORD_FILE}" ]]; then
    if [[ -t 0 ]]; then
        read -r -s -p "Vault password: " vault_password
        echo ""
        TEMP_PASS_FILE="$(mktemp)"
        chmod 600 "${TEMP_PASS_FILE}"
        echo -n "${vault_password}" > "${TEMP_PASS_FILE}"
        VAULT_PASSWORD_FILE="${TEMP_PASS_FILE}"
    else
        echo "Error: No vault password file specified." >&2
        echo "Use --vault-password-file <path>, pass the file path as an argument, or use --ask-vault-password." >&2
        exit 1
    fi
fi

if [[ ! -f "${VAULT_PASSWORD_FILE}" ]]; then
    echo "Error: Vault password file '${VAULT_PASSWORD_FILE}' not found or unreadable." >&2
    exit 1
fi

provided_input_count=0
for var_name in "${TARGET_VARS[@]}"; do
    input_file_var="${var_name}_FILE"
    if [[ -v "${input_file_var}" ]]; then
        input_file="${!input_file_var}"
        if [[ ! -r "${input_file}" || ! -s "${input_file}" ]]; then
            echo "Error: ${input_file_var} must reference a nonempty readable file." >&2
            exit 1
        fi
        provided_input_count=$((provided_input_count + 1))
    fi
done

if [[ ${provided_input_count} -eq 0 ]]; then
    echo "Error: Specify at least one nonempty <VARIABLE>_FILE rotation input." >&2
    exit 1
fi

VAULT_DISCOVERY_FILE="$(mktemp)"
if ! find -L "${REPO_ROOT}/integration-tests" -type f -regex '.*vault.*\.\(yaml\|yml\)$' \
    -exec readlink -e {} + | sort -u > "${VAULT_DISCOVERY_FILE}"; then
    echo "Error: Could not discover vault files under ${REPO_ROOT}/integration-tests." >&2
    exit 1
fi

mapfile -t VAULT_FILES < "${VAULT_DISCOVERY_FILE}"
rm -f "${VAULT_DISCOVERY_FILE}"
VAULT_DISCOVERY_FILE=""

if [[ ${#VAULT_FILES[@]} -eq 0 ]]; then
    echo "No vault files found under ${REPO_ROOT}/integration-tests"
    exit 0
fi

echo "Found ${#VAULT_FILES[@]} vault file(s) to process."

updated_count=0
processed_count=0
failed_count=0

for file in "${VAULT_FILES[@]}"; do
    relative_file="${file#${REPO_ROOT}/}"
    echo -n "Processing ${relative_file}... "
    processed_count=$((processed_count + 1))

    TEMP_DECRYPTED_FILE="$(mktemp)"

    if ! ansible-vault decrypt "${file}" --output "${TEMP_DECRYPTED_FILE}" \
        --vault-password-file "${VAULT_PASSWORD_FILE}" >/dev/null 2>&1; then
        echo "FAILED (could not decrypt file)"
        rm -f "${TEMP_DECRYPTED_FILE}"
        TEMP_DECRYPTED_FILE=""
        failed_count=$((failed_count + 1))
        continue
    fi

    if ! updated_vars="$(python3 -c '
import os, sys, re, base64
from pathlib import Path

temp_file = sys.argv[1]
target_vars = sys.argv[2:]

with open(temp_file, "r", encoding="utf-8") as f:
    content = f.read()

modified = False
updated_list = []

for var_name in target_vars:
    pattern = re.compile(rf"^([ \t]*{re.escape(var_name)}:[ \t]*).*$", re.MULTILINE)
    if pattern.search(content):
        input_file = os.environ.get(f"{var_name}_FILE")
        if input_file is None:
            continue
        try:
            raw_val = Path(input_file).read_bytes()
        except OSError as error:
            print(f"Error: could not read {var_name}_FILE: {error}", file=sys.stderr)
            sys.exit(1)
        if not raw_val:
            print(f"Error: {var_name}_FILE is empty.", file=sys.stderr)
            sys.exit(1)
        b64_val = base64.b64encode(raw_val).decode("utf-8")
        content = pattern.sub(lambda m: m.group(1) + b64_val, content)
        modified = True
        updated_list.append(var_name)

if modified:
    with open(temp_file, "w", encoding="utf-8") as f:
        f.write(content)
    print(",".join(updated_list))
' "${TEMP_DECRYPTED_FILE}" "${TARGET_VARS[@]}")"; then
        echo "FAILED (could not update file)"
        rm -f "${TEMP_DECRYPTED_FILE}"
        TEMP_DECRYPTED_FILE=""
        failed_count=$((failed_count + 1))
        continue
    fi

    if [[ -n "${updated_vars}" ]]; then
        TEMP_ENCRYPTED_FILE="$(mktemp "${file}.XXXXXX")"
        rm -f "${TEMP_ENCRYPTED_FILE}"
        if ansible-vault encrypt "${TEMP_DECRYPTED_FILE}" --output "${TEMP_ENCRYPTED_FILE}" \
            --vault-password-file "${VAULT_PASSWORD_FILE}" >/dev/null 2>&1 \
            && ansible-vault view "${TEMP_ENCRYPTED_FILE}" \
                --vault-password-file "${VAULT_PASSWORD_FILE}" >/dev/null 2>&1; then
            if mv "${TEMP_ENCRYPTED_FILE}" "${file}"; then
                TEMP_ENCRYPTED_FILE=""
                echo "UPDATED [vars: ${updated_vars}] and re-encrypted."
                updated_count=$((updated_count + 1))
            else
                echo "FAILED to replace vault with re-encrypted file!"
                failed_count=$((failed_count + 1))
            fi
        else
            echo "FAILED to re-encrypt file!"
            failed_count=$((failed_count + 1))
        fi
    else
        echo "NO CHANGE (target variables not found)"
    fi

    rm -f "${TEMP_DECRYPTED_FILE}"
    TEMP_DECRYPTED_FILE=""
    rm -f "${TEMP_ENCRYPTED_FILE}"
    TEMP_ENCRYPTED_FILE=""
done

echo "Done! Processed ${processed_count} file(s), updated ${updated_count} file(s), failed ${failed_count} file(s)."

if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi
