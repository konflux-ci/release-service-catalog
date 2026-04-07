#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="false" # Default to false

# Override merge_github_pr to include JIRA reference for simple-jira collector
merge_github_pr() {
    echo "Merging PR ${pr_number} in repo ${component_repo_name}..."
    local commit_message="This fixes CVE-2024-8260. Fixes RELEASE-1502"
    if [ "${NO_CVE}" == "true" ]; then
      echo "(Note: NOT Adding a CVE to the commit message)"
      commit_message="e2e test. Fixes RELEASE-1502"
    else
      echo "(Note: Adding CVE-2024-8260 and RELEASE-1502 to the commit message)"
    fi
    echo "Commit message: \"${commit_message}\""

    local merge_result
    local attempt=1
    local max_attempts=3
    local success=false

    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        echo "Merge attempt ${attempt}/${max_attempts}..."

        set +e
        merge_result=$(curl -L \
          -X PUT \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $GITHUB_TOKEN" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/repos/${component_repo_name}/pulls/${pr_number}/merge" \
          -d "{\"commit_title\":\"e2e test\",\"commit_message\":\"${commit_message}\"}" --silent --show-error --fail-with-body)

        if [ $? -eq 0 ]; then
            success=true
            echo "✅ PR merge succeeded on attempt ${attempt}"
        else
            echo "❌ PR merge failed on attempt ${attempt}. Response: ${merge_result}"
            if [ $attempt -lt $max_attempts ]; then
                echo "Waiting 5 seconds before retry..."
                sleep 5
            fi
        fi
        set -e

        attempt=$((attempt + 1))
    done

    if [ "$success" = false ]; then
        log_error "Failed to merge PR after ${max_attempts} attempts. Last response: ${merge_result}"
    fi

    # SHA is made global by not declaring it local
    SHA=$(jq -r '.sha' <<< "${merge_result}")
    if [ -z "$SHA" ] || [ "$SHA" == "null" ]; then
        log_error "Failed to get SHA from merge response: ${merge_result}"
    fi
    echo "Merge SHA: ${SHA}"
}

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

    # first 2 arches are specified in the pipelinerun templates, the last one is src.
    # When the release includes noarch RPMs, fanout adds extra rpmfiles (one per default arch).
    arches=("x86_64" "src")
    echo "Checking RPM files count..."
    local rpmfiles=$(jq -c '.status.artifacts.rpmfiles // []' <<< "${release_json}")
    local rpmfiles_count=$(jq -r '. | length' <<< "${rpmfiles}")
    local noarch_count
    noarch_count=$(jq -r '[.[]? | select(.arch == "noarch")] | length' <<< "${rpmfiles}")
    local expected_count=$(( ${#arches[@]} + noarch_count ))
    if [ "${rpmfiles_count}" -ne "${expected_count}" ]; then
      echo "🔴 rpmfiles count was ${rpmfiles_count}, expected ${expected_count} (${#arches[@]} base + ${noarch_count} noarch)"
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

    # When the release includes noarch RPMs, assert they are published to all default arch repos.
    if [ "${noarch_count}" -gt 0 ]; then
      echo "Checking noarch RPM fanout to default arch repos..."
      # Get arches from the rpm-repositories mapping in the RPA (excluding src)
      default_arches=$(kubectl get releaseplanadmission "${release_plan_admission_name}" \
        -n "${managed_namespace}" -ojson \
        | jq -r '.spec.data.mapping["rpm-repositories"][]? | select(.arch != "src") | .arch' \
        | sort -u)
      for default_arch in ${default_arches}; do
        local noarch_for_arch
        noarch_for_arch=$(jq -r '[.[]? | select(.arch == "noarch" and (.pulprepo | test("'"${default_arch}"'")))] | length' <<< "${rpmfiles}")
        if [ "${noarch_for_arch}" -lt 1 ]; then
          echo "🔴 noarch RPMs not published to ${default_arch} repo (count: ${noarch_for_arch})"
          failures=$((failures+1))
        else
          echo "✅️ noarch rpmfiles for ${default_arch}: ${noarch_for_arch}"
        fi
      done
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

            # Verify SBOM field is present for source RPM artifacts and is downloadable
            echo "Checking SBOM for source RPM artifacts..."
            sbom_url=$(yq '.spec.content.artifacts[] | select(.architecture == "src") | .sbom // ""' \
              "${advisory_yaml_dir}/advisory.yaml" | head -n1)

            if [ -n "${sbom_url}" ]; then
              echo "Found SBOM URL: ${sbom_url}"

              # Get Pulp credentials from the secret
              # Disable tracing to prevent credential exposure
              { set +x; } 2>/dev/null
              pulp_secret_name="pulp-credentials-${component_name}"
              cli_toml=$(kubectl get secret "${pulp_secret_name}" -n "${managed_namespace}" \
                -o jsonpath='{.data.cli\.toml}' 2>/dev/null | base64 -d || echo "")

              if [ -n "${cli_toml}" ]; then
                pulp_username=$(echo "${cli_toml}" | grep username | cut -d'"' -f2)
                pulp_password=$(echo "${cli_toml}" | grep password | cut -d'"' -f2)

                # Try to download the SBOM
                sbom_file=$(mktemp)
                http_code=$(curl -L -s -w "%{http_code}" -u "${pulp_username}:${pulp_password}" \
                  -o "${sbom_file}" "${sbom_url}" 2>/dev/null || echo "000")

                if [ "${http_code}" = "200" ]; then
                  echo "✅️ SBOM downloaded successfully (HTTP ${http_code})"
                  # Validate it's valid JSON
                  if jq -e . "${sbom_file}" >/dev/null 2>&1; then
                    echo "✅️ SBOM is valid JSON"
                  else
                    echo "🔴 SBOM is not valid JSON"
                    failures=$((failures+1))
                  fi
                else
                  echo "🔴 Failed to download SBOM (HTTP ${http_code})"
                  failures=$((failures+1))
                fi
                rm -f "${sbom_file}"
              else
                echo "Warning: Could not retrieve Pulp credentials, skipping SBOM download verification"
              fi
            else
              echo "🔴 sbom field not found in source RPM artifact entry"
              failures=$((failures+1))
            fi

            # Verify attestation field is present for source RPM artifacts and is downloadable
            echo "Checking attestation for source RPM artifacts..."
            attestation_url=$(yq '.spec.content.artifacts[] | select(.architecture == "src") | .attestation // ""' \
              "${advisory_yaml_dir}/advisory.yaml" | head -n1)

            if [ -n "${attestation_url}" ]; then
              echo "Found attestation URL: ${attestation_url}"

              # Reuse Pulp credentials from SBOM check
              if [ -n "${cli_toml}" ]; then
                # Try to download the attestation
                att_file=$(mktemp)
                http_code=$(curl -L -s -w "%{http_code}" -u "${pulp_username}:${pulp_password}" \
                  -o "${att_file}" "${attestation_url}" 2>/dev/null || echo "000")

                if [ "${http_code}" = "200" ]; then
                  echo "✅️ Attestation downloaded successfully (HTTP ${http_code})"
                  # Validate it's valid JSON
                  if jq -e . "${att_file}" >/dev/null 2>&1; then
                    echo "✅️ Attestation is valid JSON"
                  else
                    echo "🔴 Attestation is not valid JSON"
                    failures=$((failures+1))
                  fi
                else
                  echo "🔴 Failed to download attestation (HTTP ${http_code})"
                  failures=$((failures+1))
                fi
                rm -f "${att_file}"
              else
                echo "Warning: Could not retrieve Pulp credentials, skipping attestation download verification"
              fi
            else
              echo "🔴 attestation field not found in source RPM artifact entry"
              failures=$((failures+1))
            fi

            # Verify signingKey is present on all artifacts and matches the RPA value
            echo "Checking signingKey for all artifacts..."
            expected_signing_key=$(kubectl get releaseplanadmission "${release_plan_admission_name}" \
              -n "${managed_namespace}" -o jsonpath='{.spec.data.signOptions.signKeyAlias.key}')
            echo "Expected signingKey from RPA: ${expected_signing_key}"
            artifact_count=$(yq '.spec.content.artifacts | length' "${advisory_yaml_dir}/advisory.yaml")
            for ((idx=0; idx<artifact_count; idx++)); do
              signing_key=$(yq ".spec.content.artifacts[${idx}].signingKey // \"\"" "${advisory_yaml_dir}/advisory.yaml")
              if [ "${signing_key}" = "${expected_signing_key}" ]; then
                echo "✅️ Artifact ${idx} has correct signingKey: ${signing_key}"
              else
                echo "🔴 Artifact ${idx} has incorrect signingKey: '${signing_key}' (expected '${expected_signing_key}')"
                failures=$((failures+1))
              fi
            done

            # Validate advisory description contains expected RPM grouping format
            echo "Validating advisory description RPM content..."

            # Check for source RPM group header (e.g., "hello:")
            if echo "${description}" | grep -qE "^hello:$"; then
              echo "✅️ Found source RPM group header 'hello:' in description"
            else
              echo "🔴 Missing source RPM group header 'hello:' in description"
              failures=$((failures+1))
            fi

            # Check for source RPM entry with .src suffix (e.g., "hello-2.12.1-xxx.src (source)" or "(src)")
            if echo "${description}" | grep -qE "hello-.*\.src \((source|src)\)"; then
              echo "✅️ Found source RPM entry with .src suffix in description"
            else
              echo "🔴 Missing source RPM entry with .src suffix in description"
              failures=$((failures+1))
            fi

            # Check for binary RPM entry with arch (e.g., "hello-2.12.1-xxx (x86_64)")
            # Use pattern that doesn't match the .src entry
            if echo "${description}" | grep -E "hello-[0-9].*\(.*x86_64" | grep -qv "\.src"; then
              echo "✅️ Found binary RPM entry with x86_64 arch in description"
            else
              echo "🔴 Missing binary RPM entry with x86_64 arch in description"
              failures=$((failures+1))
            fi

            # Check for noarch RPM entry (e.g., "hello-data-2.12.1-xxx (noarch)")
            if echo "${description}" | grep -q "hello-data-.* (noarch)"; then
              echo "✅️ Found noarch RPM entry (hello-data) in description"
            else
              echo "🔴 Missing noarch RPM entry (hello-data) in description"
              failures=$((failures+1))
            fi

            # Check for Security Fix(es) section if CVEs are present in artifacts
            echo "Validating advisory description CVE content..."
            # Count unique CVEs across all artifacts
            cve_count=$(yq '[.spec.content.artifacts[]?.cves.fixed // {} | keys] | flatten | unique | length' "${advisory_yaml_dir}/advisory.yaml")
            if [ "${cve_count}" -gt 0 ]; then
              if echo "${description}" | grep -q "Security Fix(es):"; then
                echo "✅️ Found 'Security Fix(es):' section in description"
                # Check that at least one CVE ID is present (CVE-YYYY-NNNNN format)
                if echo "${description}" | grep -qE "CVE-[0-9]{4}-[0-9]+"; then
                  echo "✅️ Found CVE ID in description"
                else
                  echo "🔴 Missing CVE ID in 'Security Fix(es):' section"
                  failures=$((failures+1))
                fi
              else
                echo "🔴 Missing 'Security Fix(es):' section but ${cve_count} CVEs found in advisory artifacts"
                failures=$((failures+1))
              fi
            else
              echo "ℹ️ No CVEs in advisory artifacts, skipping Security Fix(es) check"
            fi

            # Check for Bug Fix(es) section if issues are present
            echo "Validating advisory description JIRA content..."
            # Count issues (simple-jira collector finds issues from commit messages)
            issue_count=$(yq '[.spec.issues.fixed[]?] | length' "${advisory_yaml_dir}/advisory.yaml")
            if [ "${issue_count}" -gt 0 ]; then
              echo "ℹ️ Found ${issue_count} issues in advisory.spec.issues.fixed"
              if echo "${description}" | grep -q "Bug Fix(es) and Enhancement(s):"; then
                echo "✅️ Found 'Bug Fix(es) and Enhancement(s):' section in description"
                # Check that RELEASE-1502 is present (from commit message "Fixes RELEASE-1502")
                if echo "${description}" | grep -q "RELEASE-1502"; then
                  echo "✅️ Found JIRA ID 'RELEASE-1502' in description"
                else
                  echo "🔴 Missing JIRA ID 'RELEASE-1502' in 'Bug Fix(es) and Enhancement(s):' section"
                  failures=$((failures+1))
                fi
              else
                echo "🔴 Missing 'Bug Fix(es) and Enhancement(s):' section but ${issue_count} issues found in advisory"
                failures=$((failures+1))
              fi
            else
              echo "ℹ️ No issues in advisory.spec.issues.fixed - simple-jira collector may not have found JIRA references"
              echo "ℹ️ Check that commit message contains 'Fixes RELEASE-1502' and collector is configured correctly"
            fi
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

      # Verify artifacts.json was created by push-unsigned-rpms-to-pulp task
      echo "Checking artifacts.json from push-unsigned-rpms-to-pulp task..."
      local artifacts_dir
      artifacts_dir=$(mktemp -d -p "$(pwd)")

      if "${SUITE_DIR}/../scripts/get-trusted-artifact-content.sh" \
          "${managed_plr_name}" \
          "push-unsigned-rpms-to-pulp" \
          "sourceDataArtifact" \
          "${managed_namespace}" \
          "${artifacts_dir}" > /dev/null 2>&1; then

        # Find artifacts.json in the extracted content
        local artifacts_json_file
        artifacts_json_file=$(find "${artifacts_dir}" -name "artifacts.json" -type f | head -1)

        if [ -n "${artifacts_json_file}" ] && [ -f "${artifacts_json_file}" ]; then
          echo "Found artifacts.json at: ${artifacts_json_file}"
          local artifacts_json_content
          artifacts_json_content=$(cat "${artifacts_json_file}")

          # Verify artifacts.json has expected structure
          if echo "${artifacts_json_content}" | jq -e '.artifacts' > /dev/null 2>&1; then
            echo "✅️ artifacts.json has 'artifacts' field"
          else
            echo "🔴 artifacts.json is missing 'artifacts' field"
            failures=$((failures+1))
          fi

          if echo "${artifacts_json_content}" | jq -e '.distributions' > /dev/null 2>&1; then
            echo "✅️ artifacts.json has 'distributions' field"
          else
            echo "🔴 artifacts.json is missing 'distributions' field"
            failures=$((failures+1))
          fi

          # Verify there are artifacts (RPMs were uploaded)
          local artifact_count
          artifact_count=$(echo "${artifacts_json_content}" | jq '.artifacts | keys | length')
          if [ "${artifact_count}" -gt 0 ]; then
            echo "✅️ artifacts.json contains ${artifact_count} artifact(s)"
          else
            echo "🔴 artifacts.json has no artifacts (expected at least 1)"
            failures=$((failures+1))
          fi

          # Verify there are distributions
          local dist_count
          dist_count=$(echo "${artifacts_json_content}" | jq '.distributions | keys | length')
          if [ "${dist_count}" -gt 0 ]; then
            echo "✅️ artifacts.json contains ${dist_count} distribution(s)"
          else
            echo "🔴 artifacts.json has no distributions"
            failures=$((failures+1))
          fi

          echo "artifacts.json content:"
          echo "${artifacts_json_content}" | jq '.'
        else
          echo "🔴 artifacts.json not found in trusted artifact"
          failures=$((failures+1))
        fi
      else
        echo "⚠️ Could not fetch trusted artifact from push-unsigned-rpms-to-pulp task (task may not have run)"
      fi

      # Cleanup
      rm -rf "${artifacts_dir}" 2>/dev/null || true
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
        "Update component source before merge. Fixes RELEASE-1502" \
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
      "Update component source before merge. Fixes RELEASE-1502" \
      "${encoded_contents}"

  echo "✅️ Successfully patched component source!"
}
