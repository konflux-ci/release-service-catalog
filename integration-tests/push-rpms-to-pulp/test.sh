#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Function to verify Release contents
verify_release_contents() {
  local failures=0
  local failed_releases
  for RELEASE_NAME in ${RELEASE_NAMES};
  do
    echo "Verifying Release contents for ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}..."
    local release_json
    release_json=$(kubectl get release/"${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" -ojson)
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${RELEASE_NAME}"
    fi
    # first 2 arches are specified in the pipelinerun templates, the last one is source.
    arches=("x86_64" "source")
    echo "Checking RPM files count..."
    local rpmfiles=$(jq -c '.status.artifacts.rpmfiles // []' <<< "${release_json}")
    local rpmfiles_count=$(jq -r '. | length' <<< "${rpmfiles}")
    if [ "${rpmfiles_count}" -ne ${#arches[@]} ]; then
      echo "🔴 rpmfiles count was not equal to the number of arches"
      failures=$((failures+1))
    fi
   for arch in "${arches[@]}"; do
    echo "Checking RPM files for ${arch}..."
    arch_rpmfiles=$(jq -r '.[]? | select(.arch == "'"${arch}"'") | .rpm // ""' <<< "${rpmfiles}")
    if [ -n "${arch_rpmfiles}" ]; then
      echo "✅️ rpmfiles for ${arch}: ${arch_rpmfiles}"
    else
      echo "🔴 rpmfiles for ${arch} was empty"
      failures=$((failures+1))
    fi
   done

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
  echo "- enable rpmbuilds"
  set +x
  # Get secret value from the tenant secrets file and use
  # it for GH_TOKEN
  secret_value=$(yq '. | select(.metadata.name | contains("pipelines-as-code-secret-")) | .stringData.password' ${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml)
  export GH_TOKEN=${secret_value}

  # Patch each PaC pipeline to add multi-arch support and source image build
  local file_names=".tekton/${component_name}-pull-request.yaml .tekton/${component_name}-push.yaml "
  for file_name in ${file_names}; do
    echo "Patching ${file_name}..."

    template_file=""
    template_contents=""

    if [[ "$file_name" == *pull-request.yaml ]]; then
        template_file="${SUITE_DIR}/resources/tenant/templates/tekton/pull-request-template.yaml"
    elif [[ "$file_name" == *push.yaml ]]; then
        template_file="${SUITE_DIR}/resources/tenant/templates/tekton/push-template.yaml"
    fi

    # Check if template file exists and read its contents
    if [[ -n "$template_file" && -f "$template_file" ]]; then
        template_contents=$(cat "$template_file" | envsubst)
        echo "✅ Found template: $template_file"
    else
        if [[ -n "$template_file" ]]; then
            echo "❌ Template not found: $template_file"
        else
            echo "ℹ️ No template mapping for: $file_name"
        fi
        exit 1
    fi

    encoded_contents=$(base64 -w 0 <<< "${template_contents}")

    "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${component_repo_name}" \
        "${pr_number}" \
        "${file_name}" \
        "Update component source before merge" \
        "${encoded_contents}"
  done

  echo "✅️ Successfully patched component source!"
}
