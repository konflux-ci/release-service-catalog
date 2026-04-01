#!/usr/bin/env bash
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Override: Create managed resources before tenant resources
# This ensures ReleasePlanAdmission exists before the Snapshot triggers auto-release
create_kubernetes_resources() {
    echo "Creating Kubernetes resources (managed first, then tenant)..."
    # tmpDir is made global by not declaring it local
    tmpDir=$(mktemp -d)
    echo "Temporary directory for resources: ${tmpDir}"

    # Resolve symlinks in resources directories for kustomize compatibility
    echo "Resolving symlinks in resources directories..."
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/tenant" "$tmpDir/tenant"
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/managed" "$tmpDir/managed"

    # IMPORTANT: Apply managed resources (including RPA) BEFORE tenant resources
    # This prevents race condition where Snapshot auto-release triggers before RPA exists
    echo "Building and applying managed resources (including ReleasePlanAdmission)..."
    kustomize build "$tmpDir/managed" | envsubst > "$tmpDir/managed-resources.yaml"
    kubectl apply -f "$tmpDir/managed-resources.yaml"

    # Link secrets to ServiceAccount
    # Since secrets are created after SA in kustomization, we need to explicitly link them
    local sa_file="$tmpDir/managed/sa.yaml"
    if [ -f "${sa_file}" ]; then
        echo "Linking secrets to ServiceAccount ${managed_sa_name}..."

        # Apply envsubst to resolve variables in SA file
        local sa_yaml_resolved
        sa_yaml_resolved=$(envsubst < "${sa_file}")

        # Extract secrets from the ServiceAccount YAML (both secrets and imagePullSecrets)
        local secrets_to_link=""
        if command -v yq &> /dev/null; then
            secrets_to_link=$(echo "$sa_yaml_resolved" | yq eval '.secrets[].name, .imagePullSecrets[].name' - 2>/dev/null | sort -u)
        else
            # Fallback: extract secret names using awk
            secrets_to_link=$(echo "$sa_yaml_resolved" | awk '
                /^secrets:/ || /^imagePullSecrets:/ { in_section=1; next }
                /^[a-zA-Z]/ { in_section=0 }
                in_section && /^\s+-\s+name:/ { gsub(/.*name:\s*/, ""); print }
            ' | sort -u)
        fi

        if [ -n "${secrets_to_link}" ]; then
            for secret_name in ${secrets_to_link}; do
                if [ -n "${secret_name}" ]; then
                    echo "  Linking secret: ${secret_name}"
                    oc secrets link "${managed_sa_name}" "${secret_name}" -n "${managed_namespace}" 2>&1 | grep -v "already linked" || true
                fi
            done
            echo "Secret linking completed."
        else
            echo "No secrets found in ServiceAccount YAML to link."
        fi
    fi

    # Wait briefly to ensure RPA is persisted before creating Snapshot
    echo "Waiting for ReleasePlanAdmission to be created..."
    local max_wait=30
    local count=0
    while ! kubectl get releaseplanadmission "${release_plan_admission_name}" -n "${managed_namespace}" &>/dev/null; do
        if [ $count -ge $max_wait ]; then
            echo "❌ Error: ReleasePlanAdmission not created after ${max_wait}s"
            exit 1
        fi
        sleep 1
        count=$((count + 1))
    done
    echo "✅ ReleasePlanAdmission ${release_plan_admission_name} exists"

    # Now create tenant resources (including Snapshot which triggers auto-release)
    echo "Building and applying tenant resources (including Snapshot)..."
    kustomize build "$tmpDir/tenant" | envsubst > "$tmpDir/tenant-resources.yaml"
    kubectl create -f "$tmpDir/tenant-resources.yaml"

    echo "Kubernetes resources applied."
}

wait_for_releases(){
    echo "Waiting for Release associated with snapshot ${snapshot_name}..."
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local FULL_NAME=""

    export RELEASE_NAMESPACE="${tenant_namespace}"

    while [ -z "${FULL_NAME}" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]; then
            echo "❌ Timeout waiting for Release to appear after ${timeout} seconds"
            echo "Snapshot: ${snapshot_name}"
            kubectl get snapshot "${snapshot_name}" -n "${tenant_namespace}" -o yaml
            exit 1
        fi

        FULL_NAME=$(kubectl get release -n "${RELEASE_NAMESPACE}" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "${snapshot_name}" || true)

        if [ -z "${FULL_NAME}" ]; then
            echo -n "."
            sleep 5
        fi
    done

    echo ""
    echo "✅ Found release: ${FULL_NAME}"
    export RELEASE_NAME="${FULL_NAME}"

    ${SUITE_DIR}/../scripts/wait-for-release.sh
}
# Function to verify Release contents
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SUITE_DIR, managed_namespace, component_name
verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."

    # Read AWS credentials from managed-secrets.yaml
    echo "Reading AWS credentials for component ${component_name}..."
    AWS_CREDENTIALS_DIR="$(mktemp -d)"
    mkdir -p "${AWS_CREDENTIALS_DIR}/.aws"

    yq '. | select(.metadata.name | contains("charon-aws-credentials-stage-")) | .data.credentials' \
        ${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml | base64 -d > "${AWS_CREDENTIALS_DIR}/.aws/credentials"

    if [ -s "${AWS_CREDENTIALS_DIR}/.aws/credentials" ]; then
        echo "✅ AWS credentials extracted successfully"
        export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDENTIALS_DIR}/.aws/credentials"
    else
        echo "🔴 Failed to extract AWS credentials for charon-aws-credentials-stage-${component_name}"
        return 1
    fi

    # List files in S3 bucket and check for recently created files (< 1 minute)
    echo "Checking S3 bucket for recently created files..."
    local s3_bucket="s3://stage-npm-npmjs/"
    local current_time=$(date +%s)
    local one_minute_ago=$((current_time - 60))

    # List all files with details
    local s3_output=$(aws --profile=ronda-stage s3 ls "${s3_bucket}" --recursive --human-readable --summarize 2>&1)
    local aws_exit_code=$?

    if [ $aws_exit_code -ne 0 ]; then
        echo "🔴 Failed to list S3 bucket: ${s3_bucket}"
        echo "${s3_output}"
        return 1
    fi

    echo "S3 bucket listing summary:"
    echo "${s3_output}" | tail -5

    # Parse and check for files created in the last 1 minute
    local recent_files=0
    while IFS= read -r line; do
        # Skip empty lines and summary lines
        if [[ -z "$line" || "$line" =~ ^Total || "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Extract date and time from S3 ls output format: YYYY-MM-DD HH:MM:SS size filename
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            local file_date="${BASH_REMATCH[1]}"
            local file_time="${BASH_REMATCH[2]}"
            local file_timestamp=$(date -d "${file_date} ${file_time}" +%s 2>/dev/null)

            if [ -n "$file_timestamp" ] && [ $file_timestamp -ge $one_minute_ago ]; then
                echo "✅ Recent file found (< 1 min): $line"
                recent_files=$((recent_files + 1))
            fi
        fi
    done <<< "${s3_output}"

    if [ $recent_files -gt 0 ]; then
        echo "✅ Found ${recent_files} file(s) created in the last 1 minute"
    else
        echo "⚠️  No files found created in the last 1 minute"
    fi
}
