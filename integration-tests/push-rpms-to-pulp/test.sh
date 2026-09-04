#!/usr/bin/env bash
# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="false" # Default to false

# Override default lifecycle functions from test-functions.sh for multi-component support.

create_github_repository() {
    echo "Creating component repositories..."

    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component_base_branch}" \
        "${component_repo_name}" "${component_branch}"

    echo "Creating component 2 repository..."
    "${SUITE_DIR}/../scripts/copy-branch-to-repo-git.sh" \
        "${component_base_repo_name}" "${component2_base_branch}" \
        "${component2_repo_name}" "${component2_branch}"
}

# --- Snapshot and Release Management ---

wait_for_multi_component_snapshot() {
    local max_attempts=24
    local attempt=1
    local snapshot_name=""

    while [ $attempt -le $max_attempts ] && [ -z "$snapshot_name" ]; do
        local all_snapshots
        all_snapshots=$(kubectl get snapshots -n "$tenant_namespace" \
            -l "appstudio.openshift.io/application=${application_name}" \
            --sort-by=.metadata.creationTimestamp \
            -o json 2>/dev/null)

        if [ $? -ne 0 ] || [ -z "$all_snapshots" ]; then
            [ $attempt -lt $max_attempts ] && sleep 5
            attempt=$((attempt + 1))
            continue
        fi

        echo "$all_snapshots" | jq -r \
          '.items[] | "  \(.metadata.name): \(.spec.components | length) components"' >&2

        snapshot_name=$(echo "$all_snapshots" | jq -r \
          '.items[] | select(.spec.components | length == 2) | .metadata.name' | tail -1)

        if [ -z "$snapshot_name" ]; then
            [ $attempt -lt $max_attempts ] && sleep 5
        fi

        attempt=$((attempt + 1))
    done

    if [ -z "$snapshot_name" ]; then
        echo "Failed to find multi-component snapshot after ${max_attempts} attempts" >&2
    fi

    echo "$snapshot_name"
}

wait_for_releases() {
    local snapshot_name
    snapshot_name=$(wait_for_multi_component_snapshot)
    if [ -z "$snapshot_name" ]; then
        echo "Could not find multi-component snapshot"
        exit 1
    fi

    local release_name="push-rpms-multi-${uuid}"

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
    export RELEASE_NAMES="${release_name}"
    release_names="${release_name}"

    "${SUITE_DIR}/../scripts/wait-for-release.sh"
}

# --- Release Verification ---

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

    local rpmfiles
    rpmfiles=$(jq -c '.status.artifacts.rpmfiles // []' <<< "${release_json}")
    local rpmfiles_count
    rpmfiles_count=$(jq -r '. | length' <<< "${rpmfiles}")

    local repo_prefix="konflux-release-integration-tests"

    _check_rpm_in_repo() {
      local label=$1 rpm_pattern=$2 repo=$3
      local count
      count=$(jq -r --arg pat "$rpm_pattern" --arg repo "$repo" \
        '[.[]? | select(.rpm | test($pat)) | select(.pulprepo == $repo)] | length' <<< "$rpmfiles")
      if [ "$count" -ge 1 ]; then
        echo "✅️ ${label}"
      else
        echo "🔴 ${label}"
        failures=$((failures+1))
      fi
    }

    _check_rpm_not_in_repo() {
      local label=$1 rpm_pattern=$2 repo=$3
      local count
      count=$(jq -r --arg pat "$rpm_pattern" --arg repo "$repo" \
        '[.[]? | select(.rpm | test($pat)) | select(.pulprepo == $repo)] | length' <<< "$rpmfiles")
      if [ "$count" -eq 0 ]; then
        echo "✅️ ${label}"
      else
        echo "🔴 ${label} (found ${count} unexpected entries)"
        failures=$((failures+1))
      fi
    }

    # Component A (hello): 2 binary (x86_64, aarch64) + 1 src + 4 noarch = 7
    # Component B (hello2): noarch-only build -> 4 noarch fanout + 1 src = 5 (no arch-specific RPMs)
    local expected_count=12
    echo "Checking RPM files count..."
    if [ "${rpmfiles_count}" -ne "${expected_count}" ]; then
      echo "🔴 rpmfiles count was ${rpmfiles_count}, expected ${expected_count}"
      failures=$((failures+1))
    else
      echo "✅️ rpmfiles count ${rpmfiles_count}"
    fi

    echo "Checking Component A (hello) binary RPMs..."
    for arch in x86_64 aarch64; do
      _check_rpm_in_repo "hello.${arch} in ${arch} repo" \
        "hello-[0-9].*\\.${arch}" "${repo_prefix}/${arch}"
    done

    echo "Checking Component A (hello) source RPM..."
    _check_rpm_in_repo "hello.src in source repo" \
      "hello-[0-9].*\\.src" "${repo_prefix}/source"

    echo "Checking Component B (hello2) has no arch-specific binary RPMs..."
    for arch in x86_64 aarch64; do
      _check_rpm_not_in_repo "hello2 must not publish .${arch} binary" \
        "hello2-[0-9].*\\.${arch}" "${repo_prefix}/${arch}"
    done

    echo "Checking Component B (hello2) source RPM..."
    _check_rpm_in_repo "hello2.src in source repo" \
      "hello2-[0-9].*\\.src" "${repo_prefix}/source"

    echo "Checking Component A (hello-data) noarch fanout..."
    for arch in x86_64 aarch64 s390x ppc64le; do
      _check_rpm_in_repo "hello-data.noarch in ${arch} repo" \
        "hello-data-" "${repo_prefix}/${arch}"
    done

    echo "Checking Component B (hello2) noarch fanout to all default arch repos..."
    for arch in x86_64 aarch64 s390x ppc64le; do
      _check_rpm_in_repo "hello2.noarch in ${arch} repo" \
        "hello2-[0-9].*\\.noarch" "${repo_prefix}/${arch}"
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

            # Verify SBOM field is present for source RPM artifacts and is downloadable
            echo "Checking SBOM for source RPM artifacts..."
            sbom_url=$(yq '[.spec.content.artifacts[] | select(.architecture == "src")] | .[0].sbom // ""' \
              "${advisory_yaml_dir}/advisory.yaml")

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
            attestation_url=$(yq '[.spec.content.artifacts[] | select(.architecture == "src")] | .[0].attestation // ""' \
              "${advisory_yaml_dir}/advisory.yaml")

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
            first_signing_key=$(yq '.spec.content.artifacts[0].signingKey // ""' "${advisory_yaml_dir}/advisory.yaml")
            if [ -n "${expected_signing_key}" ] && [ -n "${first_signing_key}" ]; then
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
            else
              echo "⏭️ Skipping signingKey check (signingKey not populated in advisory)"
            fi

            # Validate advisory description contains expected RPM grouping format
            echo "Validating advisory description RPM content..."

            # Component A (hello) group header and entries
            if echo "${description}" | grep -qE "^hello:$"; then
              echo "✅️ Found 'hello:' group header in description"
            else
              echo "🔴 Missing 'hello:' group header in description"
              failures=$((failures+1))
            fi

            if echo "${description}" | grep -qE "hello-.*\.src \((source|src)\)"; then
              echo "✅️ Found hello source RPM entry in description"
            else
              echo "🔴 Missing hello source RPM entry in description"
              failures=$((failures+1))
            fi

            for binary_arch in x86_64 aarch64; do
              if echo "${description}" | grep -E "hello-[0-9].*\(.*${binary_arch}" | grep -qv "\.src"; then
                echo "✅️ Found hello binary RPM entry with ${binary_arch} in description"
              else
                echo "🔴 Missing hello binary RPM entry with ${binary_arch} in description"
                failures=$((failures+1))
              fi
            done

            if echo "${description}" | grep -q "hello-data-.* (noarch)"; then
              echo "✅️ Found hello-data noarch entry in description"
            else
              echo "🔴 Missing hello-data noarch entry in description"
              failures=$((failures+1))
            fi

            # Component B (hello2) group header and entries
            if echo "${description}" | grep -qE "^hello2:$"; then
              echo "✅️ Found 'hello2:' group header in description"
            else
              echo "🔴 Missing 'hello2:' group header in description"
              failures=$((failures+1))
            fi

            if echo "${description}" | grep -qE "hello2-.*\.src \((source|src)\)"; then
              echo "✅️ Found hello2 source RPM entry in description"
            else
              echo "🔴 Missing hello2 source RPM entry in description"
              failures=$((failures+1))
            fi

            if echo "${description}" | grep -q "hello2-.* (noarch)"; then
              echo "✅️ Found hello2 noarch entry in description"
            else
              echo "🔴 Missing hello2 noarch entry in description"
              failures=$((failures+1))
            fi

            if echo "${description}" | grep -E "hello2-[0-9].*\(.*x86_64" | grep -qv "\.src"; then
              echo "🔴 Unexpected hello2 arch-specific binary entry in description"
              failures=$((failures+1))
            else
              echo "✅️ No hello2 arch-specific binary entries in description (noarch-only component)"
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

    # Verify SBOM submission to Atlas (process-component-sbom and process-product-sbom tasks)
    echo "Checking SBOMs uploaded to Atlas..."
    local sboms
    sboms="$(jq -r '.status.artifacts.sboms // ""' <<< "${release_json}")"

    if [ -z "${sboms}" ] || [ "${sboms}" = "null" ]; then
      echo '🔴 The release artifact does NOT contain the "sboms" field.'
      failures=$((failures+1))
    else
      # Expect 1 product SBOM and exactly 2 component SBOMs (one per component: hello, hello2)
      verify_sboms "${sboms}" 1 2
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

# Relies on "${component}_name", "${component}_repo_name" and "${component}_pr_number" variables being set for each component.
patch_components_source_before_merge() {

    # Component 1: hello package (all arches)
    local component=component
    local _v="${component}_name"
    local component_name="${!_v}"
    _v="${component}_repo_name"
    local component_repo_name="${!_v}"
    _v="${component}_pr_number"
    local pr_number="${!_v}"
    echo "Patching component source BEFORE MERGE:"
    echo "  Component: ${component_name}"
    echo "  Repository: ${component_repo_name}"
    echo "  PR Number: ${pr_number}"
    local push_template_file="push-template.yaml"
    local pull_template_file="pull-request-template.yaml"
    local hello_index=

    patch_component_source_before_merge

    # Component 2: hello2 package (x86_64 only)
    local component=component2
    local _v="${component}_name"
    local component_name="${!_v}"
    _v="${component}_repo_name"
    local component_repo_name="${!_v}"
    _v="${component}_pr_number"
    local pr_number="${!_v}"
    echo "Patching component source BEFORE MERGE:"
    echo "  Component: ${component_name}"
    echo "  Repository: ${component_repo_name}"
    echo "  PR Number: ${pr_number}"
    local push_template_file="push-template-comp2.yaml"
    local pull_template_file="pull-request-template-comp2.yaml"
    local hello_index=2

    patch_component_source_before_merge
}

# Relies on component_name, component_repo_name, pr_number, push_template_file, pull_template_file, and hello_index variables being set.
patch_component_source_before_merge() {
  set +x
  secret_value=$(yq '. | select(.metadata.name == "pipelines-as-code-secret-${component_name}") | .stringData.password' \
    ${SUITE_DIR}/resources/tenant/secrets/tenant-secrets.yaml)
  export GH_TOKEN=${secret_value}

  _patch_tekton_templates() {
    local repo=$1 pr_num=$2 comp_name=$3 pr_template=$4 push_template=$5

    local file_names=".tekton/${comp_name}-pull-request.yaml .tekton/${comp_name}-push.yaml"
    for file_name in ${file_names}; do
      local template_file=""
      if [[ "$file_name" == *pull-request.yaml ]]; then
          template_file="${SUITE_DIR}/resources/tenant/templates/tekton/${pr_template}"
      elif [[ "$file_name" == *push.yaml ]]; then
          template_file="${SUITE_DIR}/resources/tenant/templates/tekton/${push_template}"
      fi

      if [[ ! -f "$template_file" ]]; then
          echo "Template not found: $template_file"
          exit 1
      fi

      local encoded_contents
      encoded_contents=$(cat "$template_file" | envsubst | base64 -w 0)

      "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
          "${repo}" "${pr_num}" "${file_name}" \
          "Update component source before merge. Fixes RELEASE-1502" \
          "${encoded_contents}"
    done
  }

  _patch_spec_file() {
    local repo=$1 pr_num=$2 spec_template=$3 spec_name=$4

    local encoded_contents
    encoded_contents=$(cat "${SUITE_DIR}/resources/tenant/templates/${spec_template}" | envsubst | base64 -w 0)

    "${SCRIPT_DIR}/scripts/update-file-in-pull-request.sh" \
        "${repo}" "${pr_num}" "${spec_name}" \
        "Update component source before merge. Fixes RELEASE-1502" \
        "${encoded_contents}"
  }

  _patch_tekton_templates "${component_repo_name}" "${pr_number}" \
    "${component_name}" "${pull_template_file}" "${push_template_file}"
  _patch_spec_file "${component_repo_name}" "${pr_number}" "hello${hello_index}.spec" "hello.spec"
}
