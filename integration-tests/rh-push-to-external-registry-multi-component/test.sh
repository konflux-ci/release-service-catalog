#!/usr/bin/env bash
#
# test.sh - Multi-component test for rh-push-to-external-registry pipeline.
#
# Validates pushing multiple components in a single release through the
# rh-push-to-external-registry pipeline, including Pyxis image creation
# and RPM manifest verification for each component.
#
# This file is sourced by run-test.sh. Multi-component lifecycle is handled
# by the framework via PTSV_COMPONENTS="component component2" in test.env.

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# --- Snapshot and Release Management ---

wait_for_releases() {
    local snapshot_name
    snapshot_name=$(wait_for_multi_component_snapshot)
    if [ -z "${snapshot_name}" ]; then
        echo "Could not find multi-component snapshot"
        exit 1
    fi

    local release_name="rh-ext-multi-${uuid}"

    cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${release_name}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-run-uuid: "${uuid}"
spec:
  snapshot: ${snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    export RELEASE_NAME=${release_name}
    export RELEASE_NAMESPACE=${tenant_namespace}
    "${SUITE_DIR}/../scripts/wait-for-release.sh"

    export RELEASE_NAMES="${release_name}"
}

# --- Release Verification ---

verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "${release_json}" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    local failures=0
    local failed_releases=""

    # Verify multi-component images using shared helper
    check_container_images

    # Additional verification: ensure distinct URLs and shasums for multi-component test
    echo ""
    echo "Verifying distinct URLs and shasums for each component..."
    local image_count
    image_count=$(jq -r '.status.artifacts.images | length' <<< "${release_json}")

    local image0_url image0_shasum image1_url image1_shasum
    image0_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image0_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")
    image1_url=$(jq -r '.status.artifacts.images[1]?.urls[0] // ""' <<< "${release_json}")
    image1_shasum=$(jq -r '.status.artifacts.images[1]?.shasum // ""' <<< "${release_json}")

    echo "Image 0: url=${image0_url}, shasum=${image0_shasum}"
    echo "Image 1: url=${image1_url}, shasum=${image1_shasum}"

    if [ "${image0_url}" != "${image1_url}" ]; then
        echo "✅️ Image URLs are distinct"
    else
        echo "🔴 Image URLs are identical: ${image0_url}"
        failures=$((failures+1))
    fi

    if [ "${image0_shasum}" != "${image1_shasum}" ]; then
        echo "✅️ Image shasums are distinct"
    else
        echo "🔴 Image shasums are identical: ${image0_shasum}"
        failures=$((failures+1))
    fi

    echo ""
    echo "Verifying Pyxis image IDs..."

    local pyxis_url="https://pyxis.preprod.api.redhat.com/"
    local managed_plr
    managed_plr=$(jq -r '.status.managedProcessing?.pipelineRun' <<< "${release_json}")
    local managed_plr_name
    managed_plr_name=$(cut -f2 -d/ <<< "${managed_plr}")

    local uri
    uri=$("${SCRIPT_DIR}/scripts/get-taskrun-result.sh" "${managed_plr_name}" "create-pyxis-image" \
        "sourceDataArtifact" "${managed_namespace}")
    local oci_artifact="${uri#*:}"
    echo "oci_artifact: ${oci_artifact}"

    local oci_artifact_dir
    oci_artifact_dir=$(mktemp -d -p "$(pwd)")
    oras blob fetch "${oci_artifact}" --output - | tar -C "${oci_artifact_dir}" --no-overwrite-dir -zxmf -
    echo "Restored artifact to ${oci_artifact_dir}"

    local pyxisDataFile
    pyxisDataFile=$(find "${oci_artifact_dir}" -name "pyxis.json")

    local imageIds
    imageIds=$(jq -r '[.components[].pyxisImages[].imageId] | join(" ")' "${pyxisDataFile}")
    local imageIdCount
    imageIdCount=$(echo "${imageIds}" | wc -w)

    echo "Found ${imageIdCount} Pyxis image ID(s): ${imageIds}"

    if [ "${imageIdCount}" -ge 2 ]; then
        echo "✅️ Found at least 2 Pyxis image IDs (one per component)"
    else
        echo "🔴 Found only ${imageIdCount} Pyxis image ID(s), expected at least 2"
        failures=$((failures+1))
    fi

    local cert_file key_file
    cert_file="$(mktemp)"
    key_file="$(mktemp)"
    chmod 600 "${cert_file}" "${key_file}"
    local cert_secret_encoded_value key_secret_encoded_value
    cert_secret_encoded_value=$(yq '. | select(.metadata.name | contains("pyxis-")) | .data.cert' \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml")
    key_secret_encoded_value=$(yq '. | select(.metadata.name | contains("pyxis-")) | .data.key' \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml")
    base64 -d <<< "${cert_secret_encoded_value}" > "${cert_file}"
    base64 -d <<< "${key_secret_encoded_value}" > "${key_file}"

    local imageIdsFound=false
    for imageId in ${imageIds}; do
        local result_image_json
        result_image_json="$(curl --retry 3 --silent --show-error --fail-with-body \
            --cert "${cert_file}" --key "${key_file}" "${pyxis_url}v1/images/id/${imageId}")"
        local result_image_id
        result_image_id=$(jq -r '._id' <<< "${result_image_json}")
        if [ "${result_image_id}" == "${imageId}" ]; then
            echo "✅️ Found imageId: ${result_image_id} in Pyxis"
        else
            echo "🔴 imageId: ${result_image_id} did not match expected imageId: ${imageId}"
            failures=$((failures+1))
        fi

        local result_rpm_json
        result_rpm_json="$(curl --retry 3 --silent --show-error --fail-with-body \
            --cert "${cert_file}" --key "${key_file}" \
            "${pyxis_url}v1/images/id/${imageId}/rpm-manifest")"
        local rpm_manifest_id
        rpm_manifest_id=$(jq -r '._id // ""' <<< "${result_rpm_json}")
        if [ -n "${rpm_manifest_id}" ]; then
            echo "✅️ Found RPM manifest for imageId: ${imageId} in Pyxis"
        else
            echo "🔴 No RPM manifest found for imageId: ${imageId}"
            failures=$((failures+1))
        fi

        imageIdsFound=true
    done

    if [ "${imageIdsFound}" = false ]; then
        echo "🔴 No Pyxis image IDs were found"
        failures=$((failures+1))
    fi

    rm -f "${cert_file}" "${key_file}"
    rm -rf "${oci_artifact_dir}" 2>/dev/null || true

    echo ""
    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Test has FAILED with ${failures} failure(s)!"
        exit 1
    else
        echo "✅️ All multi-component release checks passed. Success!"
    fi
}
