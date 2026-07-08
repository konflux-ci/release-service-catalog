#!/usr/bin/env bash
#
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true" # Default to false

# Function to verify Release contents
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SUITE_DIR, managed_namespace
verify_release_contents() {
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    # get the oci artifact for the create-pyxis image so that we can get all the imageIds
    # created
    local pyxis_url="https://pyxis.preprod.api.redhat.com/"
    local managed_plr=$(jq -r '.status.managedProcessing?.pipelineRun' <<< "${release_json}")
    local managed_plr_name=$(cut -f2 -d/ <<< "${managed_plr}")

    local uri=$("${SCRIPT_DIR}/scripts/get-taskrun-result.sh" "${managed_plr_name}" "create-pyxis-image" \
        "sourceDataArtifact" "${managed_namespace}")
    local oci_artifact="${uri#*:}" # Assuming the URI might have a scheme like "oci:"
    echo "oci_artifact: ${oci_artifact}"

    local oci_artifact_dir=$(mktemp -d -p "$(pwd)")
    oras blob fetch "${oci_artifact}" --output - | tar -C "${oci_artifact_dir}" --no-overwrite-dir -zxmf -
    echo "Restored artifact ${ociArtifact} to ${oci_artifact_dir}"

    local failures=0
    local image_url image_arches image_shasum

    image_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image_arches=$(jq -r '.status.artifacts.images[0]?.arches // [] | sort | join(" ")' <<< "${release_json}")
    image_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")

    echo "Checking Image URL..."
    if [ -n "${image_url}" ]; then
        echo "✅️ image_url: ${image_url}"
    else
        echo "🔴 image_url was empty"
        failures=$((failures+1))
    fi

    echo "Checking image arches..."
    if [ "${image_arches}" = "amd64 arm64" ]; then
        echo "✅️ Found required image arches: amd64 arm64"
    else
        echo "🔴 Expected image arches: amd64 arm64, found: ${image_arches}"
        failures=$((failures+1))
    fi

    # Use digest instead of tag, tag can be overwritten by concurrent tests
    local image_pullspec="${image_url%:*}@${image_shasum}"

    echo "Verifying multi-arch image pullability with skopeo (${image_pullspec})..."
    AUTH_FILE="$(mktemp)"
    yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml" | base64 -d > "${AUTH_FILE}"

    for arch in amd64 arm64; do
        if skopeo inspect --authfile "${AUTH_FILE}" --override-arch "${arch}" --tls-verify=true --retry-times 3 \
                "docker://${image_pullspec}" > /dev/null 2>&1; then
            echo "✅️ skopeo inspect --override-arch ${arch} succeeded for ${image_pullspec}"
        else
            echo "🔴 skopeo inspect --override-arch ${arch} failed for ${image_pullspec}"
            failures=$((failures+1))
        fi
    done
    rm -f "${AUTH_FILE}"

    echo "Checking Image IDs..."
    pyxisDataFile=$(find ${oci_artifact_dir} -name "pyxis.json")
    imageIds=$(jq -r '[.components[].pyxisImages[].imageId] | join(" ")' "${pyxisDataFile}")
    imageIdsFound=false

    imageIdCount=$(echo "${imageIds}" | wc -w)
    if [ "${imageIdCount}" -ge 2 ]; then
        echo "✅️ Found ${imageIdCount} Pyxis image IDs (expected at least 2 for multi-arch)"
    else
        echo "🔴 Found only ${imageIdCount} Pyxis image ID(s), expected at least 2 for multi-arch"
        failures=$((failures+1))
    fi

    # prepare pyxis credentials
    cert_secret_encoded_value=$(yq '. | select(.metadata.name | contains("pyxis-")) | .data.cert' ${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml)
    key_secret_encoded_value=$(yq '. | select(.metadata.name | contains("pyxis-")) | .data.key' ${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml)
    cert_secret_value=$(base64 -d <<< "${cert_secret_encoded_value}" > /tmp/cert)
    key_secret_value=$(base64 -d <<< "${key_secret_encoded_value}" > /tmp/key)

    for imageId in ${imageIds}; do
        result_image_json="$(curl --cert /tmp/cert --key /tmp/key ${pyxis_url}v1/images/id/${imageId})"
        result_image_id=$(jq -r '._id' <<< "${result_image_json}")
        if [ "${result_image_id}" == "${imageId}" ]; then
            echo "✅️ Found imageId: ${result_image_id} in pyxis"
        else
            echo "🔴 imageId: ${result_image_id} did not match expected imageId: ${imageId}"
            failures=$((failures+1))
        fi

        # Verify RPM manifest was pushed to Pyxis for this image (validates push-rpm-data-to-pyxis ran)
        result_rpm_json="$(curl --cert /tmp/cert --key /tmp/key \
            "${pyxis_url}v1/images/id/${imageId}/rpm-manifest")"
        rpm_manifest_id=$(jq -r '._id // ""' <<< "${result_rpm_json}")
        if [ -n "${rpm_manifest_id}" ]; then
            echo "✅️ Found RPM manifest for imageId: ${imageId} in pyxis"
        else
            echo "🔴 No RPM manifest found for imageId: ${imageId}"
            failures=$((failures+1))
        fi

        imageIdsFound=true
    done

    if [ "${imageIdsFound}" = false ]; then
        echo "🔴 imageIdsFound was false. No imageIds were found."
        failures=$((failures+1))
    fi

    if [ "${failures}" -gt 0 ]; then
      echo "🔴 Test has FAILED with ${failures} failure(s)!"
      exit 1
    else
      echo "✅️ All release checks passed. Success!"
    fi
}

patch_component_source_before_merge() {
  set +x
  secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' \
      "${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml")
  export GH_TOKEN="${secret_value}"

  head_sha=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
      "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}" | jq -r '.head.sha')

  local file_names=".tekton/${component_name}-pull-request.yaml .tekton/${component_name}-push.yaml "
  for file_name in ${file_names}; do
    local work_dir
    work_dir=$(mktemp -d)
    nopath_file_name=$(basename "${file_name}")

    curl -s -H "Authorization: token ${GH_TOKEN}" \
        "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}" | \
        jq -r '.content' | base64 -d > "${work_dir}/${nopath_file_name}"

    yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) += ["linux/arm64"]' \
        "${work_dir}/${nopath_file_name}"
    encoded_contents=$(base64 -w 0 "${work_dir}/${nopath_file_name}")
    rm -rf "${work_dir}"

    "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${component_repo_name}" \
        "${pr_number}" \
        "${file_name}" \
        "Update component source before merge" \
        "${encoded_contents}"
  done
}
