#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

# Set DATA_DIR to match the task's dataDir param (for logging mock calls)
# The task uses /var/workdir/release as dataDir
DATA_DIR="${DATA_DIR:-/var/workdir/release}"
export DATA_DIR

# Mode is determined by container image name pattern (set during cosign calls)
MOCK_MODE="none"

function cosign() {
    echo $* >> ${DATA_DIR}/mock_cosign.txt
    # Extract output file and image from arguments
    local output_file=""
    local image=""
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--output-file" ]]; then
            output_file="${args[i+1]}"
        fi
        # Last argument is typically the image
        image="${args[-1]}"
    done

    # Determine mode based on image name
    if [[ "${image}" == *"alreadyexists"* ]]; then
        MOCK_MODE="all"
    elif [[ "${image}" == *"mismatch"* ]]; then
        MOCK_MODE="mismatch"
    else
        MOCK_MODE="none"
    fi
    # Persist mode for pulp calls
    echo "${MOCK_MODE}" > /tmp/mock_mode

    if [[ "$*" == *"download sbom"* ]]; then
        if [[ -n "${output_file}" ]]; then
            # Create a mock SBOM JSON file (use echo -n to match pulp mock's sha256 calculation)
            echo -n '{"bomFormat": "CycloneDX", "specVersion": "1.4", "components": []}' > "${output_file}"
        fi
        echo "Mock cosign download sbom succeeded"
    elif [[ "$*" == *"download attestation"* ]]; then
        if [[ -n "${output_file}" ]]; then
            # Create a mock attestation JSON file (use echo -n to match pulp mock's sha256 calculation)
            echo -n '{"payloadType": "application/vnd.in-toto+json", "payload": "eyJ0eXBlIjogInRlc3QifQ=="}' > "${output_file}"
        fi
        echo "Mock cosign download attestation succeeded"
    else
        echo "Error: Unexpected cosign call: $*" >&2
        exit 1
    fi
}

function pulp() {
    echo $* >> ${DATA_DIR}/mock_pulp.txt
    if [[ "$*" == *"file repository list"* ]]; then
        # Mock metadata file repository check
        echo "[ {\"name\": \"metadata\"} ]"
    elif [[ "$*" == *"file content list"* ]]; then
        # Check if file exists based on mock mode (set by cosign)
        local mode="none"
        if [[ -f /tmp/mock_mode ]]; then
            mode="$(cat /tmp/mock_mode)"
        fi
        echo "file_content_list mode=${mode} args=$*" >> ${DATA_DIR}/mock_pulp_debug.txt
        if [[ "${mode}" == "all" ]]; then
            # File exists with matching checksum
            if [[ "$*" == *".sbom"* ]]; then
                local sha256
                sha256=$(echo -n '{"bomFormat": "CycloneDX", "specVersion": "1.4", "components": []}' | sha256sum | cut -d' ' -f1)
                echo "[{\"sha256\": \"${sha256}\", \"relative_path\": \"mock.sbom\"}]"
            elif [[ "$*" == *".att"* ]]; then
                local sha256
                sha256=$(echo -n '{"payloadType": "application/vnd.in-toto+json", "payload": "eyJ0eXBlIjogInRlc3QifQ=="}' | sha256sum | cut -d' ' -f1)
                echo "[{\"sha256\": \"${sha256}\", \"relative_path\": \"mock.att\"}]"
            else
                echo "[]"
            fi
        elif [[ "${mode}" == "mismatch" ]]; then
            # File exists but with different checksum
            echo "[{\"sha256\": \"0000000000000000000000000000000000000000000000000000000000000000\", \"relative_path\": \"mock.file\"}]"
        else
            # File does not exist
            echo "[]"
        fi
    elif [[ "$*" == *"file content upload"* ]]; then
        # Mock file upload
        echo "{\"pulp_href\": \"/api/pulp/mock/api/v3/content/file/files/mock-uuid/\"}"
    else
        echo "Error: Unexpected pulp call: $*" >&2
        exit 1
    fi
}

function select-oci-auth() {
    echo "Mock select-oci-auth called with: $*" >> ${DATA_DIR}/mock_select_oci_auth.txt
    echo "{}"
}
