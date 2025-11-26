#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="false" # Default to false


verify_atlas_url() {
    local url="$1"
    local prefix="https://atlas.release.stage.devshift.net/sboms/urn:uuid:"

    if [[ ! "$url" == "$prefix"* ]]; then
        echo "🔴 Atlas URL '$url' has invalid prefix"
        return 1
    fi

    local uuid_str="${url#$prefix}"

    # UUID v7 regex pattern
    if [[ ! "$uuid_str" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
        echo "🔴 Could not parse UUID '$uuid_str' or UUID is not version 7"
        return 1
    fi

    return 0
}

verify_sboms() {
    local sboms_json="$1"
    local any_failures=0

    local product_sboms
    product_sboms=$(jq -r '.product[]? // empty' <<< "$sboms_json" 2>/dev/null)
    local product_count
    product_count=$(jq -r '.product | length // 0' <<< "$sboms_json" 2>/dev/null)

    if [ "$product_count" -eq 1 ]; then
        echo "✅️ Found expected number of product SBOMs: $product_count"
        while IFS= read -r atlas_url; do
            if [ -n "$atlas_url" ]; then
                if verify_atlas_url "$atlas_url"; then
                    echo "✅️ Valid product SBOM Atlas URL: $atlas_url"
                else
                    any_failures=1
                fi
            fi
        done <<< "$product_sboms"
    else
        echo "🔴 Incorrect number of product SBOMs. Expected 1, found: $product_count"
        any_failures=1
    fi

    local component_sboms
    component_sboms=$(jq -r '.component[]? // empty' <<< "$sboms_json" 2>/dev/null)
    local component_count
    component_count=$(jq -r '.component | length // 0' <<< "$sboms_json" 2>/dev/null)

    if [ "$component_count" -eq 3 ]; then
        echo "✅️ Found expected number of component SBOMs: $component_count"
        while IFS= read -r atlas_url; do
            if [ -n "$atlas_url" ]; then
                if verify_atlas_url "$atlas_url"; then
                    echo "✅️ Valid component SBOM Atlas URL: $atlas_url"
                else
                    any_failures=1
                fi
            fi
        done <<< "$component_sboms"
    else
        echo "🔴 Incorrect number of component SBOMs. Expected 3, found: $component_count"
        any_failures=1
    fi

    if [ "$any_failures" -eq 1 ]; then
        failures=$((failures+1))
    fi
}

# Function to verify Release contents
# Modifies global variable: advisory_yaml_dir
# Relies on global variables: RELEASE_NAME, RELEASE_NAMESPACE, SCRIPT_DIR, managed_namespace, managed_sa_name, NO_CVE
verify_release_contents() {
  local failed_releases
  for RELEASE_NAME in ${RELEASE_NAMES};
  do
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi

    local failures=0
    local num_issues advisory_url advisory_internal_url catalog_url cve
    local severity topic description

    num_issues=$(jq -r '.status.collectors.tenant."jira-collector".releaseNotes.issues.fixed | length // 0' <<< "${release_json}")
    advisory_url=$(jq -r '.status.artifacts.advisory.url // ""' <<< "${release_json}")
    advisory_internal_url=$(jq -r '.status.artifacts.advisory.internal_url // ""' <<< "${release_json}")
    catalog_url=$(jq -r '.status.artifacts.catalog_urls[]?.url // ""' <<< "${release_json}")
    cve=$(jq -r '.status.collectors.tenant.cve.releaseNotes.cves[]? | select(.key == "CVE-2024-8260") | .key // ""' <<< "${release_json}")
    image_arches=$(jq -r '.status.artifacts.images[0].arches | sort | join(" ") // ""' <<< "${release_json}")
    sboms=$(jq -r '.status.artifacts.sboms // ""' <<< "${release_json}")

    echo "Checking image arches..."
    if [ "$image_arches" = "amd64 arm64" ]; then
      echo "✅️ Found required image arches: amd64 arm64"
    else
      echo "🔴 Some required image arches were NOT found: expected: amd64 arm64, found: ${image_arches}"
      failures=$((failures+1))
    fi

    if [ -z "$advisory_internal_url" ]; then
        echo "Warning: advisory_internal_url is empty. Skipping advisory content check."
    else
        # advisory_yaml_dir is made global by not declaring it local
        advisory_yaml_dir=$(mktemp -d -p "$(pwd)")
        echo "Fetching advisory content to ${advisory_yaml_dir}..."
        "${SUITE_DIR}/../scripts/get-advisory-content.sh" "${managed_namespace}" "${managed_sa_name}" "${advisory_internal_url}" "${advisory_yaml_dir}"
        if [ ! -f "${advisory_yaml_dir}/advisory.yaml" ]; then
            echo "🔴 Advisory YAML not found at ${advisory_yaml_dir}/advisory.yaml"
            failures=$((failures+1))
        else
            severity=$(yq '.spec.severity // "null"' "${advisory_yaml_dir}/advisory.yaml")
            echo "Found severity: ${severity}"
            topic=$(yq '.spec.topic // ""' "${advisory_yaml_dir}/advisory.yaml")
            echo "Found topic: ${topic}"
            description=$(yq '.spec.description // ""' "${advisory_yaml_dir}/advisory.yaml")
            echo "Found description: ${description}"
        fi
    fi

    echo "Checking number of issues..."
    if [ "${num_issues}" -gt 0 ]; then
      echo "✅️ Number of issues (${num_issues}) is > 0"
    else
      echo "🔴 Incorrect number of issues. Found ${num_issues}, expected > 0"
      failures=$((failures+1))
    fi

    echo "Checking advisory URLs..."
    if [ -n "${advisory_url}" ]; then
      echo "✅️ advisory_url: ${advisory_url}"
    else
      echo "🔴 advisory_url was empty!"
      failures=$((failures+1))
    fi
    if [ -n "${advisory_internal_url}" ]; then
      echo "✅️ advisory_internal_url: ${advisory_internal_url}"
    else
      echo "🔴 advisory_internal_url was empty!"
      failures=$((failures+1))
    fi
    if [ -n "${catalog_url}" ]; then
        echo "✅️ catalog_url: ${catalog_url}"
    else
        echo "🟡 catalog_url was empty (optional?)" # Marked as optional based on original script's handling
        # If this should be a failure, uncomment the next line
        # failures=$((failures+1))
    fi

    if [ "${NO_CVE}" == "true" ]; then
      echo "Checking that no CVEs were found (as NO_CVE is true)..."
      if [ -z "${cve}" ]; then
        echo "✅️ CVE: <empty>"
      else
        echo "🔴 Incorrect CVE. Expected empty, Found '${cve}'!"
        failures=$((failures+1))
      fi
      local expected_severity="null"
      echo "Checking if severity is '${expected_severity}' (since NO_CVE is true)..."
       if [[ "${severity}" == "${expected_severity}" ]]; then
        echo "✅️ Found correct severity: ${severity}"
      else
        echo "🔴 Incorrect severity! Expected '${expected_severity}', Found '${severity}'"
        failures=$((failures+1))
      fi
    else
      echo "Checking that CVE 'CVE-2024-8260' was found..."
      if [ "${cve}" == "CVE-2024-8260" ]; then
        echo "✅️ CVE: ${cve}"
      else
        echo "🔴 Incorrect CVE. Expected 'CVE-2024-8260', Found '${cve}'!"
        failures=$((failures+1))
      fi
      local expected_severity="Moderate"
      echo "Checking if severity is ${expected_severity} (since NO_CVE is false)..."
      if [[ "${severity}" == "${expected_severity}" ]]; then
        echo "✅️ Found correct severity: ${severity}"
      else
        echo "🔴 Incorrect severity! Expected '${expected_severity}', Found '${severity}'"
        failures=$((failures+1))
      fi
    fi

    if [ -n "$advisory_internal_url" ] && [ -f "${advisory_yaml_dir}/advisory.yaml" ]; then
      local expected_topic_substring="Updated Application Stream container images for Red Hat Comp2 are now available"
      echo "Checking if topic contains '${expected_topic_substring}'..."
      if [[ "${topic}" == *"${expected_topic_substring}"* ]]; then
        echo "✅️ Found topic substring in: ${topic}"
      else
        echo "🔴 Did not find topic substring in: ${topic}!"
        failures=$((failures+1))
      fi

      substrings=(
          "Red Hat Comp2 1 container images"
          "* rh-advisories-component"
          "RELEASE-1502 (test issue for collector e2e testing)"
      )
      # Conditionally add CVE-2024-8260 to substrings if NO_CVE is false
      if [ "${NO_CVE}" == "false" ]; then
        substrings+=("CVE-2024-8260")
      fi

      all_found=true
      for substring in "${substrings[@]}"; do
          if grep -qF -- "$substring" <<< "${description}"; then
              echo "✅ Found: '$substring'"
          else
              echo "❌ Not Found: '$substring'"
              all_found=false
          fi
      done

      if [ "$all_found" = true ]; then
        echo "✅️ Found all required description substrings"
      else
        echo "🔴 Some required description substrings were NOT found."
        failures=$((failures+1))
      fi

    elif [ -n "$advisory_internal_url" ]; then
      echo "🔴 Skipping topic and description check as advisory YAML was not found/fetched."
    else
      echo "Skipping topic and description check as advisory_internal_url was empty."
    fi

    echo "Checking SBOMs uploaded to Atlas..."
    if [ -z "$sboms" ] || [ "$sboms" = "null" ]; then
      echo '🔴 The release artifact does NOT contain the "sboms" field.'
      failures=$((failures+1))
    else
      verify_sboms "$sboms"
    fi

    if [ "${failures}" -gt 0 ]; then
      echo "🔴 Test has FAILED with ${failures} failure(s)!"
      failed_releases="${RELEASE_NAME} ${failed_releases}"
    else
      echo "✅️ All release checks passed. Success!"
    fi
  done

  if [ -n "${failed_releases}" ]; then
    echo "🔴 Releases FAILED: ${failed_releases}"
    exit 1
  else
    echo "✅️ Success!"
  fi

}

patch_component_source_before_merge() {
  echo "Patching component source BEFORE MERGE to:"
  echo "- Add multi-arch support to the PaC pipeline"
  echo "- Add source image build to the PaC pipeline"
  set +x
  # Get secret value from the tenant secrets file and use
  # it for GH_TOKEN
  secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' ${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml)
  export GH_TOKEN=${secret_value}

  # Patch each PaC pipeline to add multi-arch support and source image build
  local file_names=".tekton/${component_name}-pull-request.yaml .tekton/${component_name}-push.yaml "
  for file_name in ${file_names}; do
    echo "Patching ${file_name}..."
    head_sha=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
    "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}" | jq -r '.head.sha')

    decoded_contents=$(curl -s -H "Authorization: token ${GH_TOKEN}" \
        "https://api.github.com/repos/${component_repo_name}/contents/${file_name}?ref=${head_sha}" | \
        jq -r '.content' | base64 -d)

    local work_dir=$(mktemp -d)
    nopath_file_name=$(basename "${file_name}")
    echo "${decoded_contents}" > "${work_dir}/${nopath_file_name}"
    yq -i '(.spec.params[] | select(.name == "build-platforms") | .value) += ["linux/arm64"]' "${work_dir}/${nopath_file_name}"
    yq -i '.spec.params += [{"name": "build-source-image", "value": "true"}]' "${work_dir}/${nopath_file_name}"
    encoded_contents=$(base64 -w 0 <<< "$(cat "${work_dir}/${nopath_file_name}")")
    rm -rf "${work_dir}"

    "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${component_repo_name}" \
        "${pr_number}" \
        "${file_name}" \
        "Update component source before merge" \
        "${encoded_contents}"
  done

  echo "✅️ Successfully patched component source!"
}
