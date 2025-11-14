#!/usr/bin/env bash
set -eux

function curl() {
    file_path="/tmp/schema"
    if [[ "$*" == *"https://get-local-schema.com"* ]]; then
        # Extract the JSON content from configMap
        kubectl get configmap check-data-keys-schema -o jsonpath='{.data.dataKeys}' > "$file_path"
        # Verify the file is not empty and contains valid JSON
        test -s "$file_path" || { echo "Schema file is empty from configMap"; exit 1; }
        jq empty "$file_path" || { echo "Schema file is not valid JSON from configMap"; exit 1; }
    else
        command curl -Ls --fail-with-body "$@" -o "$file_path"
    fi
}
