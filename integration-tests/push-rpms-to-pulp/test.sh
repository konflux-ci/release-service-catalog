#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="false" # Default to false

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

    jq '.status' <<< "${release_json}"
    advisory_url=$(jq -r '.status.artifacts.advisory.url // ""' <<< "${release_json}")
    advisory_internal_url=$(jq -r '.status.artifacts.advisory.internal_url // ""' <<< "${release_json}")

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

    # Verify the managed PipelineRun executed the RPM filtering task (this is a key pipeline behavior).
    managed_plr_full=$(jq -r '.status.managedProcessing.pipelineRun // ""' <<< "${release_json}")
    if [ -z "${managed_plr_full}" ]; then
      echo "🔴 managedProcessing.pipelineRun is empty for ${RELEASE_NAME}"
      failures=$((failures+1))
    else
      managed_plr_name=$(basename "${managed_plr_full}")
      echo "Checking managed PipelineRun ${managed_plr_name} for filter task execution..."

      filter_tr_count=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json \
        | jq -r '[.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="filter-already-released-advisory-rpms")] | length')

      if [ "${filter_tr_count}" -ne 1 ]; then
        echo "🔴 Expected exactly 1 TaskRun for filter-already-released-advisory-rpms, got ${filter_tr_count}"
        failures=$((failures+1))
      else
        filter_tr_name=$(kubectl get taskrun -n "${managed_namespace}" \
          -l "tekton.dev/pipelineRun=${managed_plr_name}" -o json \
          | jq -r '.items[] | select(.metadata.labels."tekton.dev/pipelineTask"=="filter-already-released-advisory-rpms") | .metadata.name')
        filter_tr_status=$(kubectl get taskrun "${filter_tr_name}" -n "${managed_namespace}" \
          -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")

        if [ "${filter_tr_status}" != "True" ]; then
          echo "🔴 filter-already-released-advisory-rpms TaskRun did not succeed: ${filter_tr_name} (status=${filter_tr_status})"
          failures=$((failures+1))
        else
          echo "✅️ filter-already-released-advisory-rpms TaskRun succeeded: ${filter_tr_name}"
        fi
      fi
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

    if [ "${failures}" -gt 0 ]; then
      echo "🔴 Test has FAILED with ${failures} failure(s)!"
      failed_releases="${RELEASE_NAME} ${failed_releases}"
    else
      # Create and validate a retriggered Release using the same releasePlan/snapshot.
      # This verifies idempotency: the second run should detect that RPMs are already published
      # and filter them out (skip_release=true).
      echo "Creating retrigger Release for ${RELEASE_NAME}..."

      local prev_author prev_releaseplan prev_snapshot retrigger_name retrigger_yaml retrigger_suffix
      prev_author="$(jq -r '.metadata.labels["release.appstudio.openshift.io/author"] // .status.attribution.author // ""' <<< "${release_json}")"
      prev_releaseplan="$(jq -r '.spec.releasePlan // ""' <<< "${release_json}")"
      prev_snapshot="$(jq -r '.spec.snapshot // ""' <<< "${release_json}")"
      # Release names must be <= 63 chars; use a short unique suffix.
      retrigger_suffix="${uuid:-$(date +%s)}"
      retrigger_suffix="${retrigger_suffix:0:8}"
      retrigger_name="retrigger-${retrigger_suffix}"

      if [[ -z "${prev_author}" || -z "${prev_releaseplan}" || -z "${prev_snapshot}" ]]; then
        echo "🔴 Could not determine author/releasePlan/snapshot from ${RELEASE_NAME} for retrigger test"
        echo "  author='${prev_author}' releasePlan='${prev_releaseplan}' snapshot='${prev_snapshot}'"
        failures=$((failures+1))
      else
        # Ensure re-runs don't fail due to name collisions.
        kubectl delete release "${retrigger_name}" -n "${RELEASE_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

        retrigger_yaml="$(cat <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${retrigger_name}
  namespace: ${RELEASE_NAMESPACE}
  labels:
    release.appstudio.openshift.io/automated: "false"
    release.appstudio.openshift.io/author: "${prev_author}"
spec:
  releasePlan: ${prev_releaseplan}
  snapshot: ${prev_snapshot}
EOF
)"

        echo "${retrigger_yaml}" | kubectl create -f - >/dev/null

        # Wait for the retrigger release to reach a terminal state using the shared helper.
        # Do not immediately fail the whole test if it fails; we still want to assert it failed
        # for the expected (filtering) reason.
        echo "Waiting for retrigger Release ${retrigger_name} to complete..."
        local retrigger_rc=0
        set +e
        RELEASE_NAME="${retrigger_name}" RELEASE_NAMESPACE="${RELEASE_NAMESPACE}" \
          "${SUITE_DIR}/../scripts/wait-for-release.sh"
        retrigger_rc=$?
        set -e

        local released_status released_reason released_message retrigger_json
        retrigger_json="$(kubectl get release/"${retrigger_name}" -n "${RELEASE_NAMESPACE}" -ojson 2>/dev/null || echo "")"
        released_status="$(jq -r '.status.conditions[]? | select(.type=="Released") | .status // ""' <<< "${retrigger_json}")"
        released_reason="$(jq -r '.status.conditions[]? | select(.type=="Released") | .reason // ""' <<< "${retrigger_json}")"
        released_message="$(jq -r '.status.conditions[]? | select(.type=="Released") | .message // ""' <<< "${retrigger_json}")"

        if [[ ${retrigger_rc} -eq 0 ]]; then
          echo "✅ Retrigger Release succeeded: ${RELEASE_NAMESPACE}/${retrigger_name}"
        else
          echo "⚠️ Retrigger Release failed: ${RELEASE_NAMESPACE}/${retrigger_name}"
          echo "  message: ${released_message}"
        fi

        # Verify filter task produced skip_release=true in the managed PipelineRun.
        local retrigger_managed_plr_full retrigger_managed_plr_name skip_release_value
        retrigger_managed_plr_full="$(jq -r '.status.managedProcessing.pipelineRun // ""' <<< "${retrigger_json}")"
        if [[ -z "${retrigger_managed_plr_full}" ]]; then
          echo "🔴 retrigger managedProcessing.pipelineRun is empty for ${retrigger_name}"
          failures=$((failures+1))
        else
          retrigger_managed_plr_name="$(basename "${retrigger_managed_plr_full}")"
          skip_release_value="$("${SUITE_DIR}/../scripts/get-taskrun-result.sh" \
            "${retrigger_managed_plr_name}" \
            "filter-already-released-advisory-rpms" \
            "skip_release" \
            "${managed_namespace}" 2>/dev/null || echo "")"

          if [[ "${skip_release_value}" != "true" ]]; then
            echo "🔴 Expected skip_release=true for retrigger run; got '${skip_release_value}'"
            failures=$((failures+1))
          else
            echo "✅ skip_release=true for retrigger run (already-released RPMs were filtered)"
          fi
        fi
      fi

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

  echo "Patching hello.spec..."

  template_file="${SUITE_DIR}/resources/tenant/templates/hello.spec"
  file_name="hello.spec"

  template_contents=$(cat "$template_file" | envsubst)

  encoded_contents=$(base64 -w 0 <<< "${template_contents}")

  "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
      "${component_repo_name}" \
      "${pr_number}" \
      "${file_name}" \
      "Update component source before merge" \
      "${encoded_contents}"

  echo "✅️ Successfully patched component source!"
}
