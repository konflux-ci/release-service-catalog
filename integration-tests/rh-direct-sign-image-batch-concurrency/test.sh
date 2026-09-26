#!/usr/bin/env bash
#
# rh-direct-sign-image-batch-concurrency test script
#
# Regression test for the "concurrent signing batches delete each other's
# InternalRequest" incident fixed by the creator-pod label in
# cleanup_existing_requests() (release-service-utils PR #1045).
#
# Forces rh_direct_sign_image.py to split a single component's tags into
# TARGET_BATCH_COUNT (default 2) signing batches, which submit_batches()
# then submits concurrently via ThreadPoolExecutor. The exact tag count
# needed is computed at runtime (utils/compute_batch_tag_count.py) from the
# real signing ConfigMap and resolved image digest, rather than guessed.
#
# No component build occurs — this reuses the "skip build, static pre-built
# image" pattern from rh-advisories-large-snapshot (see resources shared via
# symlink from that suite).
#
# For general test infrastructure and requirements, see:
#   integration-tests/README.md (common setup, cluster architecture, secrets)
#
# --- Script Directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Global Script Variables (Defaults) ---
CLEANUP="true"
NO_CVE="true"

# --- Timeout Configuration (in seconds, configurable via environment) ---
SNAPSHOT_READY_TIMEOUT="${SNAPSHOT_READY_TIMEOUT:-60}"
SNAPSHOT_READY_POLL_INTERVAL="${SNAPSHOT_READY_POLL_INTERVAL:-2}"

RELEASE_START_TIMEOUT="${RELEASE_START_TIMEOUT:-600}"  # 10 minutes
RELEASE_START_POLL_INTERVAL="${RELEASE_START_POLL_INTERVAL:-5}"

CONSOLE_URL=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}" \
    | sed 's/api/konflux-ui.apps/g' | sed 's/:6443//g')
CONSOLE_URL="${CONSOLE_URL%/}/"

# Explicit allowlist for envsubst — prevents corrupting Ansible vault markers ($ANSIBLE_VAULT...).
readonly ENVSUBST_ALLOWLIST='$application_name $component_branch $component_git_url $component_name $ec_public_key_ref $managed_namespace $managed_sa_name $originating_tool $release_plan_admission_name $release_plan_name $tenant_namespace $tenant_sa_name $RELEASE_CATALOG_GIT_REVISION $RELEASE_CATALOG_GIT_URL $BATCH_TEST_TIMEOUT'

# The single static pre-built image this test signs. Reuses the first entry
# of rh-advisories-large-snapshot's stable image pool (via relative path, not
# a copy) so both suites stay in sync with whichever image that pool uses.
readonly STATIC_IMAGE_POOL_FILE="${SCRIPT_DIR}/../rh-advisories-large-snapshot/resources/static-image-pool-stable.txt"

# Cleanup function for temporary directory
cleanup_tmpdir() {
    local tmp_path="${tmpDir:-}"
    [ -z "${tmp_path}" ] && return 0
    if [ ! -d "${tmp_path}" ]; then
        echo "⚠️  Warning: tmpDir path '${tmp_path}' is not a directory, skipping cleanup" >&2
        return 0
    fi
    case "${tmp_path}" in
        /tmp/*) ;;
        *)
            echo "❌ Error: tmpDir path '${tmp_path}' is not within /tmp, refusing to delete for safety" >&2
            return 1
            ;;
    esac
    if [ "${CLEANUP}" == "true" ]; then
        echo "Cleaning up temporary directory: ${tmp_path}" >&2
        rm -rf "${tmp_path}" || echo "⚠️  Warning: Failed to remove temporary directory: ${tmp_path}" >&2
    else
        echo "Skipping tmpDir cleanup (--skip-cleanup): ${tmp_path}" >&2
    fi
}
trap cleanup_tmpdir EXIT

# Generic polling helper with timeout.
# Usage: wait_for_condition "description" timeout_seconds poll_interval_seconds condition_function_name [args...]
wait_for_condition() {
    local description="$1"
    local timeout="$2"
    local poll_interval="$3"
    local condition_function="$4"

    : "${description:?description parameter is required}"
    : "${timeout:?timeout parameter is required}"
    : "${poll_interval:?poll_interval parameter is required}"
    : "${condition_function:?condition_function parameter is required}"

    if ! declare -F "${condition_function}" >/dev/null 2>&1; then
        echo "❌ Error: condition function '${condition_function}' does not exist" >&2
        return 1
    fi

    shift 4

    echo "Waiting for ${description} (timeout: ${timeout}s)..." >&2
    local start_time
    start_time=$(date +%s)

    while true; do
        local current_time elapsed
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if (( elapsed >= timeout )); then
            echo "❌ Timeout waiting for ${description} after ${timeout}s" >&2
            return 1
        fi

        if "$condition_function" "$@"; then
            echo "✅ ${description}" >&2
            return 0
        fi

        sleep "$poll_interval"
    done
}

# --- Skip-build overrides ---
# This test signs a single static pre-built image; no component build is needed.
patch_components_source() {
    echo "⏩ Skipping component source patch - no builds needed"
}

wait_for_components_initialization() {
    echo "⏩ Skipping component initialization - using pre-built image"
}

patch_components_source_before_merge() {
    echo "⏩ Skipping component source patch - no builds needed"
}

merge_github_prs() {
    echo "⏩ Skipping PR merge - using pre-built image"
}

wait_for_plrs_to_appear() {
    echo "⏩ Skipping PLR wait - no builds triggered"
}

wait_for_plrs_to_complete() {
    echo "⏩ Skipping PLR completion - no builds needed"
}

# Name of the signing ConfigMap read by both rh_direct_sign_image.py in
# production and compute_batch_tag_count.py here. Signing key resolution
# itself (SIG_KEY_NAMES/SIG_KEY_NAME parsing) happens inside
# compute_batch_tag_count.py via the real get_signing_keys() import — no
# bash-side reimplementation needed.
readonly SIGNING_CONFIGMAP_NAME="hacbs-signing-pipeline-config-staging-e2e-pq"

# Resolve the single static test image's tag to a concrete digest reference.
# Sets the global TEST_IMAGE_DIGEST (sha256:<hex>, digest only, no repo prefix).
resolve_test_image_digest() {
    if [ ! -f "${STATIC_IMAGE_POOL_FILE}" ]; then
        echo "❌ Static image pool file not found: ${STATIC_IMAGE_POOL_FILE}" >&2
        return 1
    fi

    local image_ref
    image_ref=$(sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//' "${STATIC_IMAGE_POOL_FILE}" | grep -v '^$' | head -1)
    if [ -z "${image_ref}" ]; then
        echo "❌ Static image pool file is empty: ${STATIC_IMAGE_POOL_FILE}" >&2
        return 1
    fi

    echo "Resolving test image digest for ${image_ref}..." >&2

    local attempt digest
    for attempt in 1 2 3; do
        [ "${attempt}" -gt 1 ] && sleep $(( attempt * 3 ))
        if digest=$(skopeo inspect --retry-times 3 --format '{{.Digest}}' "docker://${image_ref}" 2>/dev/null) \
                && [ -n "${digest}" ]; then
            TEST_IMAGE_REPO="${image_ref%:*}"
            TEST_IMAGE_DIGEST="${digest}"
            export TEST_IMAGE_REPO TEST_IMAGE_DIGEST
            echo "✅ Resolved digest: ${TEST_IMAGE_DIGEST}" >&2
            return 0
        fi
        echo "⚠️  resolve_test_image_digest: attempt ${attempt}/3 failed for ${image_ref}" >&2
    done

    echo "❌ Could not resolve digest for ${image_ref}" >&2
    return 1
}

# Compute the exact number of tags needed to force rh-direct-sign-image's
# batch_signing_items() to split into exactly TARGET_BATCH_COUNT batches.
# compute_batch_tag_count.py imports and calls the real
# collect_signing_items()/batch_signing_items()/get_all_image_digests()/
# get_signing_keys() from rh_direct_sign_image.py directly (importable here —
# this suite's test-runner image is built FROM release-service-utils), so the
# computed count matches production exactly, including multi-arch digest
# expansion and the quay.io->registry.redhat.io repo conversion apply-mapping
# performs. Requires resolve_test_image_digest to have run.
# Sets the global NUM_BATCH_TAGS and BATCH_TAG_LIST (space-separated array
# variable, one tag per element).
compute_batch_tag_count() {
    : "${TEST_IMAGE_REPO:?resolve_test_image_digest must run first}"
    : "${TEST_IMAGE_DIGEST:?resolve_test_image_digest must run first}"
    : "${managed_namespace:?managed_namespace must be set}"
    : "${BATCH_TAG_PREFIX:?BATCH_TAG_PREFIX must be set}"
    : "${TARGET_BATCH_COUNT:?TARGET_BATCH_COUNT must be set}"

    # This is the same "url" used in resources/managed/rpa.yaml's mapping —
    # must stay in sync with that file.
    local signing_repo="quay.io/redhat-pending/rhtap----rh-advisories-component"

    echo "Computing tag count for exactly ${TARGET_BATCH_COUNT} signing batch(es)..." >&2

    local computed_count
    computed_count=$(python3 "${SCRIPT_DIR}/utils/compute_batch_tag_count.py" \
        --source-image "${TEST_IMAGE_REPO}@${TEST_IMAGE_DIGEST}" \
        --signing-repo "${signing_repo}" \
        --configmap-name "${SIGNING_CONFIGMAP_NAME}" \
        --namespace "${managed_namespace}" \
        --tag-prefix "${BATCH_TAG_PREFIX}" \
        --batch-limit 15000 \
        --target-batches "${TARGET_BATCH_COUNT}" \
        --margin 5) || {
        echo "❌ Failed to compute batch tag count" >&2
        return 1
    }

    if ! [[ "${computed_count}" =~ ^[0-9]+$ ]]; then
        echo "❌ compute_batch_tag_count.py did not return a valid integer: '${computed_count}'" >&2
        return 1
    fi

    NUM_BATCH_TAGS="${computed_count}"
    export NUM_BATCH_TAGS

    BATCH_TAG_LIST=()
    local i tag
    for (( i=0; i<NUM_BATCH_TAGS; i++ )); do
        tag=$(printf '%s-%04d' "${BATCH_TAG_PREFIX}" "${i}")
        BATCH_TAG_LIST+=("${tag}")
    done

    echo "✅ Computed ${NUM_BATCH_TAGS} tags to force ${TARGET_BATCH_COUNT} signing batch(es)" >&2
}

# Condition check: is the snapshot created and persisted?
check_batch_test_snapshot_ready() {
    local snapshot_name="$1"
    local namespace="$2"
    [ -n "$(kubectl get snapshot "${snapshot_name}" -n "${namespace}" -o jsonpath='{.metadata.name}' 2>/dev/null)" ]
}

# Build the Snapshot manifest: exactly one component referencing the single
# resolved static image (no tags here — tags live on the RPA mapping, patched
# by patch_rpa_with_batch_tags()).
create_batch_test_snapshot() {
    : "${tmpDir:?tmpDir must be set}"
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"
    : "${application_name:?application_name must be set}"
    : "${component_name:?component_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${TEST_IMAGE_REPO:?resolve_test_image_digest must run first}"
    : "${TEST_IMAGE_DIGEST:?resolve_test_image_digest must run first}"

    local snapshot_file="${tmpDir}/batch-test-snapshot.yaml"

    cat > "${snapshot_file}" <<EOF
---
apiVersion: appstudio.redhat.com/v1alpha1
kind: Snapshot
metadata:
  name: "${batch_test_snapshot_name}"
  namespace: "${tenant_namespace}"
  labels:
    appstudio.openshift.io/application: "${application_name}"
  annotations:
    test.appstudio.openshift.io/description: "Single-component snapshot for rh-direct-sign-image batch concurrency testing"
    # Skip build since we're using a pre-built container image
    test.appstudio.openshift.io/skip-build: "true"
    # Skip idempotency to allow re-testing with the same snapshot data
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  application: "${application_name}"
  displayName: "rh-direct-sign-image batch concurrency test snapshot"
  displayDescription: "Single component, ${NUM_BATCH_TAGS:-N} tags, forces >=2 concurrent signing batches"
  artifacts: {}
  components:
    - name: "${component_name}"
      containerImage: "${TEST_IMAGE_REPO}@${TEST_IMAGE_DIGEST}"
      source:
        git:
          url: "https://github.com/hacbs-release-tests/e2e-base"
          revision: "main"
EOF

    echo "✅ Batch test snapshot manifest created: ${snapshot_file}" >&2
    echo "${snapshot_file}"
}

apply_batch_test_snapshot() {
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"

    echo "Applying batch test snapshot to cluster..." >&2

    if [ -z "${BATCH_TEST_SNAPSHOT_FILE:-}" ] || [ ! -f "${BATCH_TEST_SNAPSHOT_FILE}" ]; then
        BATCH_TEST_SNAPSHOT_FILE=$(create_batch_test_snapshot) || return 1
    fi

    kubectl apply -f "${BATCH_TEST_SNAPSHOT_FILE}" -n "${tenant_namespace}" || {
        echo "❌ Failed to apply snapshot to namespace ${tenant_namespace}" >&2
        return 1
    }

    wait_for_condition \
        "snapshot ${batch_test_snapshot_name} to be ready" \
        "$SNAPSHOT_READY_TIMEOUT" \
        "$SNAPSHOT_READY_POLL_INTERVAL" \
        check_batch_test_snapshot_ready \
        "${batch_test_snapshot_name}" \
        "${tenant_namespace}" || {
        echo "❌ Failed waiting for snapshot to be ready" >&2
        return 1
    }

    echo "✅ Batch test snapshot applied and ready" >&2
}

create_release_for_batch_test() {
    : "${tmpDir:?tmpDir must be set}"
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${originating_tool:?originating_tool must be set}"
    : "${release_plan_name:?release_plan_name must be set}"

    echo "Creating Release CR for batch test..." >&2

    local release_file="${tmpDir}/release.yaml"

    cat > "${release_file}" <<EOF
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${batch_test_snapshot_name}-release
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
  annotations:
    # Allow re-running this test with the same snapshot
    test.appstudio.openshift.io/skip-idempotency: "true"
spec:
  snapshot: ${batch_test_snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    kubectl apply -f "${release_file}" -n "${tenant_namespace}" || {
        echo "❌ Failed to apply Release CR to namespace ${tenant_namespace}" >&2
        return 1
    }

    echo "✅ Release CR created: ${batch_test_snapshot_name}-release" >&2
}

# Patch the RPA's mapping.components[0].repositories[0].tags with the computed
# tag list. Must run BEFORE the snapshot is applied — the ReleasePlan has
# auto-release=true, so release-service fires the moment the snapshot lands;
# if the RPA still had its empty tags placeholder at that point, apply-mapping
# would produce zero signing items.
patch_rpa_with_batch_tags() {
    : "${managed_namespace:?managed_namespace must be set}"
    : "${release_plan_admission_name:?release_plan_admission_name must be set}"
    if [ "${#BATCH_TAG_LIST[@]}" -eq 0 ]; then
        echo "❌ BATCH_TAG_LIST is empty — compute_batch_tag_count must run first" >&2
        return 1
    fi

    local tags_json
    tags_json=$(printf '%s\n' "${BATCH_TAG_LIST[@]}" | jq -R . | jq -sc .)

    echo "Patching ReleasePlanAdmission ${release_plan_admission_name} with ${#BATCH_TAG_LIST[@]} tags..." >&2

    # A JSON merge patch can't target a single array element (mapping.components[0]),
    # so the whole mapping.components array is read back, patched in memory with the
    # computed tags, and written back wholesale. Safe here since this suite's RPA
    # always has exactly one component entry (index 0).
    local patch_json current_rpa patched_components
    current_rpa=$(kubectl get releaseplanadmission "${release_plan_admission_name}" -n "${managed_namespace}" -o json) || {
        echo "❌ Failed to read ReleasePlanAdmission ${release_plan_admission_name}" >&2
        return 1
    }
    patched_components=$(jq --argjson tags "${tags_json}" \
        '.spec.data.mapping.components[0].repositories[0].tags = $tags | .spec.data.mapping.components' \
        <<< "${current_rpa}")

    patch_json=$(jq -n --argjson components "${patched_components}" \
        '{ spec: { data: { mapping: { components: $components } } } }')

    if ! kubectl patch releaseplanadmission "${release_plan_admission_name}" \
            -n "${managed_namespace}" \
            --type merge \
            -p "${patch_json}"; then
        echo "❌ Failed to patch ReleasePlanAdmission" >&2
        return 1
    fi

    echo "✅ ReleasePlanAdmission patched with ${#BATCH_TAG_LIST[@]} unique tags" >&2
}

# Override: full resource creation flow for this suite.
create_kubernetes_resources() {
    : "${SUITE_DIR:?SUITE_DIR must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"

    echo "Creating Kubernetes resources for batch concurrency test..." >&2

    decrypt_secrets "${SUITE_DIR}" || {
        echo "❌ Failed to decrypt secrets" >&2
        return 1
    }

    tmpDir=$(mktemp -d)
    if [ $? -ne 0 ] || [ -z "${tmpDir}" ]; then
        echo "❌ Failed to create temporary directory" >&2
        return 1
    fi
    echo "Using temporary directory: ${tmpDir}" >&2

    # Resolve symlinks before handing directories to kustomize — kustomize
    # refuses to load symlinked files that point outside the kustomization
    # root, and several files here are intentionally symlinked from
    # rh-advisories-large-snapshot (see integration-tests/README.md
    # contributing guideline #7).
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/tenant" "${tmpDir}/tenant"
    resolve_symlinks_for_kustomize "${SUITE_DIR}/resources/managed" "${tmpDir}/managed"

    : "${RELEASE_CATALOG_GIT_URL:?RELEASE_CATALOG_GIT_URL must be set (required for ReleasePlanAdmission)}"
    : "${RELEASE_CATALOG_GIT_REVISION:?RELEASE_CATALOG_GIT_REVISION must be set (required for ReleasePlanAdmission)}"

    # Pool image is already signed by Tekton Chains — use its public key for EC policy
    # (matches rh-advisories-large-snapshot's ec-policy.yaml, symlinked into this suite).
    export ec_public_key_ref="k8s://openshift-pipelines/public-key"

    echo "Building and applying tenant resources..." >&2
    kustomize build "${tmpDir}/tenant" | envsubst "${ENVSUBST_ALLOWLIST}" > "${tmpDir}/tenant-resources.yaml" || {
        echo "❌ Failed to build tenant resources" >&2
        return 1
    }
    kubectl apply -f "${tmpDir}/tenant-resources.yaml" -n "${tenant_namespace}" || {
        echo "❌ Failed to apply tenant resources" >&2
        return 1
    }

    echo "Building and applying managed resources..." >&2
    kustomize build "${tmpDir}/managed" | envsubst "${ENVSUBST_ALLOWLIST}" > "${tmpDir}/managed-resources.yaml" || {
        echo "❌ Failed to build managed resources" >&2
        return 1
    }
    kubectl apply -f "${tmpDir}/managed-resources.yaml" -n "${managed_namespace}" || {
        echo "❌ Failed to apply managed resources" >&2
        return 1
    }

    resolve_test_image_digest || return 1
    compute_batch_tag_count || return 1

    # Generate the snapshot manifest and patch the RPA before applying the
    # snapshot (same ordering rationale as rh-advisories-large-snapshot):
    # the ReleasePlan has auto-release=true, so applying the snapshot first
    # could fire a Release against an RPA that still has zero tags.
    BATCH_TEST_SNAPSHOT_FILE=$(create_batch_test_snapshot) || return 1

    patch_rpa_with_batch_tags || return 1

    apply_batch_test_snapshot || return 1
    create_release_for_batch_test || return 1

    echo "✅ All Kubernetes resources created successfully" >&2
}

# Condition check: is the release processing?
check_batch_release_processing() {
    local release_name="$1"
    local namespace="$2"
    local pipelinerun
    pipelinerun=$(kubectl get release "${release_name}" -n "${namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || echo "")
    [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]
}

wait_for_batch_release_to_start() {
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"

    local release_name="${batch_test_snapshot_name}-release"
    echo "  Release: ${release_name}" >&2

    wait_for_condition \
        "release ${release_name} to start processing" \
        "$RELEASE_START_TIMEOUT" \
        "$RELEASE_START_POLL_INTERVAL" \
        check_batch_release_processing \
        "${release_name}" \
        "${tenant_namespace}" || {
        echo "❌ Release did not start processing within ${RELEASE_START_TIMEOUT}s" >&2
        return 1
    }

    local pipelinerun pipelinerun_name
    pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || echo "")
    pipelinerun_name="${pipelinerun##*/}"

    if [ -n "$pipelinerun" ] && [ "$pipelinerun" != "null" ]; then
        echo "  PipelineRun: ${pipelinerun}" >&2
        [[ -n "${CONSOLE_URL:-}" ]] && \
            echo "  PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun_name}" >&2
    fi

    echo "✅ Release started processing" >&2
}

# Capture a compact managed-pipeline failure summary into
# /tmp/generate-snapshot-error.txt so it surfaces in the test-report
# FAILURE_CONTEXT result. Called after wait-for-release.sh exits non-zero.
diagnose_managed_pipeline_failure() {
    local release_name="${batch_test_snapshot_name}-release"

    local pipelinerun pipelinerun_name
    pipelinerun=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null || true)
    pipelinerun_name="${pipelinerun##*/}"
    { [ -z "${pipelinerun_name}" ] || [ "${pipelinerun_name}" = "null" ]; } && return 0

    local failed_rows
    failed_rows=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${pipelinerun_name}" \
        -o json 2>/dev/null \
        | jq -r '.items[]
            | select(.status.conditions[0].status == "False")
            | [
                .metadata.labels["tekton.dev/pipelineTask"],
                .metadata.name,
                .status.podName,
                .status.conditions[0].message
              ] | @tsv') || true

    [ -z "${failed_rows}" ] && return 0

    {
        printf 'Managed pipeline failed\n'
        printf '  PipelineRun: %s\n' "${pipelinerun_name}"
        while IFS=$'\t' read -r task_name taskrun_name pod_name condition_msg; do
            printf '\n  Failed task : %s\n' "${task_name}"
            printf '  TaskRun     : %s\n' "${taskrun_name}"
            printf '  Condition   : %s\n' "${condition_msg}"
            if [ -n "${pod_name}" ] && [ "${pod_name}" != "null" ]; then
                local log_errors
                log_errors=$(kubectl logs "${pod_name}" -n "${managed_namespace}" \
                    --all-containers 2>/dev/null \
                    | grep -iE 'fatal|error|FAILED|403|404|Forbidden|Not Found' \
                    | tail -5 || true)
                if [ -n "${log_errors}" ]; then
                    printf '  Error lines :\n'
                    while IFS= read -r line; do
                        printf '    %s\n' "${line}"
                    done <<< "${log_errors}"
                fi
            fi
        done <<< "${failed_rows}"
    } > /tmp/generate-snapshot-error.txt

    echo "🔍 Managed pipeline failure context captured → test-report will show details" >&2
}

wait_for_releases() {
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"

    local release_name="${batch_test_snapshot_name}-release"

    kubectl patch release "${release_name}" -n "${tenant_namespace}" \
      --type merge \
      -p "{\"metadata\":{\"labels\":{\"originating-tool\":\"${originating_tool}\",\"test-run-uuid\":\"${uuid}\"}}}"

    echo "Waiting for release to start processing..." >&2
    wait_for_batch_release_to_start || log_error "Failed to wait for release to start"

    export RELEASE_NAME="${release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    export RELEASE_NAMES="${RELEASE_NAME}"

    echo "Waiting for release pipeline to complete..." >&2
    if ! "${SUITE_DIR}/../scripts/wait-for-release.sh"; then
        diagnose_managed_pipeline_failure
        return 1
    fi
}

# --- Verification ---
#
# The primary regression signal for the concurrent-batch-deletion bug: the
# rh-direct-sign-image TaskRun must succeed on its FIRST attempt (zero
# retries) and its pod log must show exactly TARGET_BATCH_COUNT batches all
# succeeding, with no InternalRequest-not-found / ApiException errors that
# would indicate one batch's cleanup deleted another batch's still-running
# InternalRequest.
verify_release_contents() {
    : "${batch_test_snapshot_name:?batch_test_snapshot_name must be set}"
    : "${tenant_namespace:?tenant_namespace must be set}"
    : "${managed_namespace:?managed_namespace must be set}"

    local release_name="${batch_test_snapshot_name}-release"
    local verification_failed=false

    echo "Verifying Release contents for ${release_name} in namespace ${tenant_namespace}..." >&2

    local release_json
    release_json=$(kubectl get release/"${release_name}" -n "${tenant_namespace}" -ojson 2>/dev/null || echo "")
    if [ -z "$release_json" ]; then
        echo "❌ Could not retrieve Release JSON for ${release_name}" >&2
        return 1
    fi

    local succeeded
    succeeded=$(echo "$release_json" | jq -r '.status.conditions[] | select(.type=="Released") | .status' 2>/dev/null || echo "")
    echo "Release Released condition: ${succeeded}" >&2

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Automated Verification Checks:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    # ========================================================================
    # CHECK 1: Release succeeded
    # ========================================================================
    echo "" >&2
    echo "1️⃣  Checking Release status..." >&2
    if [ "$succeeded" == "True" ]; then
        echo "   ✅ Release succeeded (Released=True)" >&2
    else
        echo "   ❌ FAILURE: Release did not succeed (Released=${succeeded})" >&2
        verification_failed=true
    fi

    local pipelinerun pipelinerun_name
    pipelinerun=$(echo "$release_json" | jq -r '.status.managedProcessing.pipelineRun' 2>/dev/null || echo "")
    pipelinerun_name="${pipelinerun##*/}"

    if [ -z "$pipelinerun" ] || [ "$pipelinerun" == "null" ]; then
        echo "   ⚠️  WARNING: PipelineRun not available, cannot run remaining checks" >&2
        verification_failed=true
    else
        echo "   PipelineRun: ${pipelinerun}" >&2
        [[ -n "${CONSOLE_URL:-}" ]] && \
            echo "   PipelineRun URL: ${CONSOLE_URL}k8s/ns/${managed_namespace}/tekton.dev~v1~PipelineRun/${pipelinerun_name}" >&2

        # ====================================================================
        # CHECK 2: rh-direct-sign-image TaskRun succeeded with ZERO retries
        # ====================================================================
        echo "" >&2
        echo "2️⃣  Checking rh-direct-sign-image TaskRun for retries..." >&2

        local sign_taskrun_json
        sign_taskrun_json=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=rh-direct-sign-image" \
            -o json 2>/dev/null || echo "{}")

        local sign_taskrun_name sign_status retries_count sign_pod_name
        sign_taskrun_name=$(jq -r '.items[0].metadata.name // ""' <<< "${sign_taskrun_json}")

        if [ -z "${sign_taskrun_name}" ]; then
            echo "   ❌ FAILURE: rh-direct-sign-image TaskRun not found" >&2
            echo "      Possible cause: task was skipped (check skip_release result upstream)" >&2
            verification_failed=true
        else
            echo "   TaskRun: ${sign_taskrun_name}" >&2

            sign_status=$(jq -r '.items[0].status.conditions[] | select(.type=="Succeeded") | .status // ""' <<< "${sign_taskrun_json}")
            retries_count=$(jq -r '.items[0].status.retriesStatus // [] | length' <<< "${sign_taskrun_json}")
            sign_pod_name=$(jq -r '.items[0].status.podName // ""' <<< "${sign_taskrun_json}")

            if [ "${sign_status}" == "True" ]; then
                echo "   ✅ rh-direct-sign-image TaskRun succeeded" >&2
            else
                echo "   ❌ FAILURE: rh-direct-sign-image TaskRun did not succeed (status=${sign_status})" >&2
                verification_failed=true
            fi

            echo "   retriesStatus count: ${retries_count} (must be 0 — a retry here means a batch failed," \
                "which is exactly the symptom of the concurrent-cleanup bug)" >&2
            if [ "${retries_count}" -eq 0 ]; then
                echo "   ✅ Zero retries — no batch failure forced a re-attempt" >&2
            else
                echo "   ❌ FAILURE: rh-direct-sign-image retried ${retries_count} time(s)" >&2
                echo "      This is the primary regression signal: a signing batch failed" >&2
                echo "      (e.g. its InternalRequest was deleted by a concurrent sibling's cleanup)" >&2
                verification_failed=true
            fi

            # ================================================================
            # CHECK 3: Pod log shows exactly TARGET_BATCH_COUNT batches, all
            # succeeded, with no InternalRequest cross-deletion errors.
            # ================================================================
            echo "" >&2
            echo "3️⃣  Inspecting rh-direct-sign-image pod log..." >&2

            if [ -z "${sign_pod_name}" ] || [ "${sign_pod_name}" == "null" ]; then
                echo "   ⚠️  WARNING: pod already garbage-collected, cannot inspect log" >&2
                verification_failed=true
            else
                local pod_log
                pod_log=$(kubectl logs "${sign_pod_name}" -n "${managed_namespace}" --all-containers 2>/dev/null || echo "")

                if [ -z "${pod_log}" ]; then
                    echo "   ⚠️  WARNING: could not retrieve pod log for ${sign_pod_name}" >&2
                    verification_failed=true
                else
                    local wrote_line submit_line summary_line
                    wrote_line=$(grep -oE "Wrote [0-9]+ batch\(es\) to" <<< "${pod_log}" | tail -1 || true)
                    submit_line=$(grep -oE "Submitting [0-9]+ batch file\(s\)" <<< "${pod_log}" | tail -1 || true)
                    summary_line=$(grep -oE "Batch request summary: [0-9]+ succeeded, [0-9]+ failed" <<< "${pod_log}" | tail -1 || true)

                    echo "   ${wrote_line:-<no 'Wrote N batch(es)' line found>}" >&2
                    echo "   ${submit_line:-<no 'Submitting N batch file(s)' line found>}" >&2
                    echo "   ${summary_line:-<no 'Batch request summary' line found>}" >&2

                    local written_count
                    written_count=$(grep -oE "Wrote [0-9]+ batch" <<< "${wrote_line}" | grep -oE "[0-9]+" || echo "")

                    if [ "${written_count}" == "${TARGET_BATCH_COUNT}" ]; then
                        echo "   ✅ Exactly ${TARGET_BATCH_COUNT} batch(es) were written (as intended)" >&2
                    else
                        echo "   ❌ FAILURE: expected exactly ${TARGET_BATCH_COUNT} batch(es), found '${written_count:-none}'" >&2
                        echo "      The computed tag count no longer produces the intended batch split —" >&2
                        echo "      re-run compute_batch_tag_count.py against the current signing ConfigMap." >&2
                        verification_failed=true
                    fi

                    if [[ "${summary_line}" == *"${TARGET_BATCH_COUNT} succeeded, 0 failed"* ]]; then
                        echo "   ✅ All batches succeeded, none failed" >&2
                    else
                        echo "   ❌ FAILURE: batch summary does not show all-succeeded: '${summary_line:-<missing>}'" >&2
                        verification_failed=true
                    fi

                    local error_lines
                    error_lines=$(grep -iE "Internal request failed for batch|Batch request failure|404|ApiException" <<< "${pod_log}" || true)
                    if [ -z "${error_lines}" ]; then
                        echo "   ✅ No 404/ApiException/'Internal request failed' errors in log" >&2
                    else
                        echo "   ❌ FAILURE: found error line(s) indicating a batch failure:" >&2
                        while IFS= read -r line; do
                            echo "      ${line}" >&2
                        done <<< "${error_lines}"
                        verification_failed=true
                    fi
                fi
            fi
        fi
    fi

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Verification Summary:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    if [ "$verification_failed" == "true" ]; then
        echo "" >&2
        echo "❌ VERIFICATION FAILED: One or more automated checks found issues" >&2
        {
            echo "FAILED"
            echo "Release: ${release_name:-unknown} | PipelineRun: ${pipelinerun_name:-unknown}"
            echo "One or more verification checks failed — see step log for details."
        } > /tmp/verification-summary.txt
        return 1
    else
        echo "" >&2
        echo "✅ SUCCESS: All automated verification checks passed" >&2
        echo "  ✅ Release succeeded" >&2
        echo "  ✅ rh-direct-sign-image succeeded with zero retries" >&2
        echo "  ✅ Exactly ${TARGET_BATCH_COUNT} concurrent signing batches ran, all succeeded" >&2
        {
            echo "PASSED"
            echo "Release: ${release_name:-unknown} | PipelineRun: ${pipelinerun_name:-unknown}"
            echo "rh-direct-sign-image: 0 retries, ${TARGET_BATCH_COUNT} batches succeeded"
        } > /tmp/verification-summary.txt
        return 0
    fi
}

# Override: cleanup with batch-test-specific resources
cleanup_resources() {
    local err=${1:-0}
    local line=${2:-"N/A"}
    local command=${3:-"N/A"}

    if [ "$err" -ne 0 ]; then
        echo "$0: ERROR: Command '$command' failed at line $line - exited with status $err"
    fi

    if [ "${CLEANUP}" == "true" ]; then
        echo "Performing cleanup..."
        set +eo pipefail

        if [ -n "${component_repo_name:-}" ]; then
            echo "🗑️  Deleting GitHub repository ${component_repo_name} ..."
            "${SUITE_DIR}/../scripts/delete-repository.sh" "${component_repo_name}" || \
                echo "   ⚠ Failed to delete GitHub repository ${component_repo_name}" >&2
        fi

        if [ -n "${component_git_url:-}" ] && [ -n "${tenant_namespace:-}" ]; then
            echo "🗑️  Removing webhook secret entry for ${component_git_url} ..."
            "${SUITE_DIR}/../scripts/remove-webhook-secret-entry.sh" "${tenant_namespace}" "${component_git_url}" || \
                echo "   ⚠ Failed to remove webhook secret entry for ${component_git_url}" >&2
        fi

        if [ -n "${batch_test_snapshot_name:-}" ] && [ -n "${tenant_namespace:-}" ]; then
            echo "🗑️  Deleting batch test snapshot ${batch_test_snapshot_name} ..."
            kubectl delete snapshot "${batch_test_snapshot_name}" -n "${tenant_namespace}" --ignore-not-found=true 2>/dev/null || \
                echo "   ⚠ Failed to delete snapshot ${batch_test_snapshot_name}" >&2
        fi

        echo "🗑️  Cleaning up test releases (originating-tool=${originating_tool:-rh-direct-sign-image-batch-concurrency-test})..."
        local old_releases
        old_releases=$(kubectl get release -n "${tenant_namespace:-dev-release-team-tenant}" \
            -l "originating-tool=${originating_tool:-rh-direct-sign-image-batch-concurrency-test}" \
            --no-headers 2>/dev/null | awk '{print $1}' || echo "")

        if [ -n "${old_releases}" ]; then
            while IFS= read -r release; do
                if kubectl delete release "${release}" -n "${tenant_namespace:-dev-release-team-tenant}" 2>/dev/null; then
                    echo "   ✓ Deleted ${release}"
                else
                    echo "   ⚠ Failed to delete ${release}"
                fi
            done <<< "${old_releases}"
        else
            echo "   ✓ No test releases found"
        fi

        if [ -n "$tmpDir" ] && [ -d "$tmpDir" ]; then
            echo "Deleting test resources..."
            if [ -f "$tmpDir/tenant-resources.yaml" ]; then
                kubectl delete rolebinding,serviceaccount,releaseplan \
                    -n "${tenant_namespace:-dev-release-team-tenant}" \
                    -l "originating-tool=${originating_tool:-rh-direct-sign-image-batch-concurrency-test}" \
                    --ignore-not-found=true 2>/dev/null || true
            fi
            if [ -f "$tmpDir/managed-resources.yaml" ]; then
                kubectl delete -f "$tmpDir/managed-resources.yaml" 2>/dev/null || true
            fi
            rm -rf "${tmpDir}" || echo "   ⚠ Failed to remove tmpDir"
        fi
    else
        echo "Skipping cleanup as per --skip-cleanup flag."
    fi

    echo "Killing any child processes..."
    pkill -e -P $$ 2>/dev/null || true

    if [ "$err" -ne 0 ]; then
        exit "$err"
    fi
}

echo "✅ Batch concurrency test functions loaded"
