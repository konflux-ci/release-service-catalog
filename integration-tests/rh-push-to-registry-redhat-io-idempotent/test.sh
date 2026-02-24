#!/usr/bin/env bash
#
# test.sh - Test-specific functions for rh-push-to-registry-redhat-io-idempotent
#
# This test validates idempotent release behavior for rh-push-to-registry-redhat-io by:
#   1. Verifying the first (auto-created) release pushed components (pyxis, signing, fileUpdates)
#   2. Creating a second release with the SAME snapshot
#   3. Verifying the second release filtered all components (idempotency)
#
# This file is sourced by run-test.sh
#

# --- Global Script Variables (Defaults) ---
CLEANUP="true"

# Function called before test starts (before any releases are created)
# This is the entry point for test initialization
test_setup() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Test Setup: Pre-flight Checks"
    echo "════════════════════════════════════════════════════════════════════"
    
    # Critical: Check Pyxis availability BEFORE wasting time on first release
    # If Pyxis is down, abort early
    # Run check FROM CLUSTER to avoid local SSL/CA issues
    check_pyxis_from_cluster "${managed_namespace}" "${component_name}"
    
    echo "✅ Pre-flight checks passed. Proceeding with test..."
    echo ""
}

# Helper: Get PipelineRun name from Release CR
# Returns just the PipelineRun name (without namespace prefix)
get_pipelinerun_name_from_release() {
    local release_name=$1

    local pipelinerun_full
    pipelinerun_full=$(kubectl get release "${release_name}" -n "${tenant_namespace}" \
        -o jsonpath='{.status.managedProcessing.pipelineRun}' 2>/dev/null)

    if [ -z "${pipelinerun_full}" ]; then
        return 1
    fi

    basename "${pipelinerun_full}"
}

# Helper: Get release as JSON
get_release_json() {
    local release_name=$1
    kubectl get release "${release_name}" -n "${tenant_namespace}" -o json
}

# Check if all components were filtered (idempotency validation)
# Returns 0 (true) if push-snapshot task was skipped, 1 (false) otherwise
were_all_components_filtered() {
    local release_name=$1

    is_taskrun_skipped "${release_name}" "push-snapshot"
}

# Check if a specific task was skipped in the pipeline, given a known PipelineRun name.
# Returns 0 (true) if task was skipped, 1 (false) otherwise
is_task_skipped_in_plr() {
    local pipelinerun_name=$1
    local task_name=$2

    local skipped_task
    skipped_task=$(kubectl get pipelinerun "${pipelinerun_name}" -n "${managed_namespace}" \
        -o jsonpath="{.status.skippedTasks[?(@.name=='${task_name}')].name}" 2>/dev/null)

    [[ -n "${skipped_task}" ]]
}

# Check if a specific task was skipped in the pipeline
# Returns 0 (true) if task was skipped, 1 (false) otherwise
is_taskrun_skipped() {
    local release_name=$1
    local task_name=$2

    local pipelinerun_name
    pipelinerun_name=$(get_pipelinerun_name_from_release "${release_name}") || return 1

    is_task_skipped_in_plr "${pipelinerun_name}" "${task_name}"
}

# Verify a single release has valid artifacts (catalog_url, file_update_mr_url, image)
# Adapted from rh-push-to-registry-redhat-io verify_release_contents
verify_single_release() {
    local release_name=$1
    echo "Verifying Release contents for ${release_name}..."

    local release_json
    release_json=$(get_release_json "${release_name}")
    if [ -z "$release_json" ]; then
        log_error "Could not retrieve Release JSON for ${release_name}"
    fi

    local failures=0
    local image_url image_arch image_shasum
    local catalog_url file_update_mr_url

    image_url=$(jq -r '.status.artifacts.images[0]?.urls[0] // ""' <<< "${release_json}")
    image_arch=$(jq -r '.status.artifacts.images[0]?.arches[0] // ""' <<< "${release_json}")
    image_shasum=$(jq -r '.status.artifacts.images[0]?.shasum // ""' <<< "${release_json}")
    catalog_url=$(jq -r '.status.artifacts.catalog_urls[]?.url // ""' <<< "${release_json}")
    file_update_mr_url=$(jq -r '.status.artifacts.merge_requests[0]?.url // ""' <<< "${release_json}")

    echo "Checking Catalog URL..."
    if [ -n "${catalog_url}" ]; then
        echo "✅️ catalog_url: ${catalog_url}"
    else
        echo "🔴 catalog_url was empty"
        failures=$((failures+1))
    fi

    # file_update_mr_url is optional: idempotent test RPA has no fileUpdates
    echo "Checking File Update MR URL..."
    if [ -n "${file_update_mr_url}" ]; then
        echo "✅️ file_update_mr_url: ${file_update_mr_url}"
    else
        echo "⚠️ file_update_mr_url empty (expected when RPA has no fileUpdates)"
    fi

    echo "Checking Image URL..."
    if [ -n "${image_url}" ]; then
        echo "✅️ image_url: ${image_url}"
    else
        echo "🔴 image_url was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Arch..."
    if [ -n "${image_arch}" ]; then
        echo "✅️ image_arch: ${image_arch}"
    else
        echo "🔴 image_arch was empty"
        failures=$((failures+1))
    fi

    echo "Checking Image Shasum..."
    if [ -n "${image_shasum}" ]; then
        echo "✅️ image_shasum: ${image_shasum}"
    else
        echo "🔴 image_shasum was empty"
        failures=$((failures+1))
    fi

    echo "Verifying image pullability with skopeo..."
    local ORIGINAL_PULLSPEC="${image_url}"
    local STRIPPED_PULLSPEC

    if [[ "$ORIGINAL_PULLSPEC" == *":"* && "$ORIGINAL_PULLSPEC" != *"@"* ]]; then
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%:*}"
        echo "Stripped tag from: $ORIGINAL_PULLSPEC -> $STRIPPED_PULLSPEC"
    elif [[ "$ORIGINAL_PULLSPEC" == *"@"* ]]; then
        STRIPPED_PULLSPEC="${ORIGINAL_PULLSPEC%@*}"
        echo "Stripped digest from: $ORIGINAL_PULLSPEC -> $STRIPPED_PULLSPEC"
    else
        STRIPPED_PULLSPEC="$ORIGINAL_PULLSPEC"
        echo "No tag or digest found, using original as is: $STRIPPED_PULLSPEC"
    fi

    local COMPLETE_PULLSPEC="${STRIPPED_PULLSPEC}@${image_shasum}"
    echo "New complete pullspec: $COMPLETE_PULLSPEC"

    DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG

    yq '. | select(.metadata.name | contains("push-")) | .data.".dockerconfigjson"' \
        "${SUITE_DIR}/resources/managed/secrets/managed-secrets.yaml" | base64 -d > "${DOCKER_CONFIG}/config.json"

    if skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}" &>/dev/null; then
        echo "✅️ Image '$COMPLETE_PULLSPEC' can be pulled using skopeo."
    else
        echo "🔴 Failed to pull or inspect image '$COMPLETE_PULLSPEC'."
        skopeo inspect --tls-verify=true "docker://${COMPLETE_PULLSPEC}"
        failures=$((failures+1))
    fi

    if [ "${failures}" -gt 0 ]; then
        echo "🔴 Release verification FAILED with ${failures} failure(s)!"
        return 1
    else
        echo "✅️ All release checks passed."
        return 0
    fi
}

# Function to verify Release contents - called by run-test.sh after first release completes
# Implements idempotent test logic:
#   1. Verify first release pushed components
#   2. Create second release with same snapshot
#   3. Verify second release filtered all components
# Check Pyxis availability by running a Job in the cluster
# This avoids local SSL/CA bundle issues and tests from the same network as pipeline tasks
# Args: $1 = managed namespace, $2 = component name
# Returns: 0 if available, exits on failure
check_pyxis_from_cluster() {
    local managed_namespace="$1"
    local component_name="$2"
    local pyxis_secret_name="pyxis-${component_name}"
    local job_name="pyxis-preflight-${uuid}"
    
        echo "════════════════════════════════════════════════════════════════════"
        echo "  Pre-flight Check: Pyxis Stage Availability (from cluster)"
        echo "════════════════════════════════════════════════════════════════════"
        
        local max_job_attempts=2
        local job_attempt=0
        local job_created=false
        
        while [ $job_attempt -lt $max_job_attempts ]; do
            job_attempt=$((job_attempt + 1))
            echo "Creating verification Job (attempt $job_attempt/$max_job_attempts)..."
            
            # Create Job that checks Pyxis connectivity FROM the cluster
            if cat <<EOF | kubectl apply -f - 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${managed_namespace}
spec:
  ttlSecondsAfterFinished: 60
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: check
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
                      set +e
                      echo "Testing Pyxis from cluster network..."
                      echo "Endpoint: https://pyxis.preprod.api.redhat.com/v1/repositories?page_size=1"
                      echo ""
                      
                      # Verify credentials exist
                      if [ ! -f /etc/pyxis/cert ] || [ ! -f /etc/pyxis/key ]; then
                        echo "❌ ERROR: Pyxis credentials not mounted"
                        exit 1
                      fi
                      
                      # Configure CA bundle if available
                      if [ -f /mnt/trusted-ca/ca-bundle.crt ]; then
                        CA_ARGS="--cacert /mnt/trusted-ca/ca-bundle.crt"
                        echo "Using cluster CA bundle"
                      else
                        CA_ARGS=""
                        echo "No CA bundle (using system defaults)"
                      fi
                      
                      echo ""
                      echo "Checking Pyxis with retries (max 3 attempts)..."
                      
                      max_retries=2
                      retry_delay=5
                      attempt=0
                      
                      while [ \$attempt -le \$max_retries ]; do
                        http_code=\$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \$CA_ARGS \
                          --cert /etc/pyxis/cert --key /etc/pyxis/key \
                          "https://pyxis.preprod.api.redhat.com/v1/repositories?page_size=1" 2>/dev/null || echo "000")
                        
                        echo "Attempt \$((attempt + 1)): HTTP \${http_code}"
                        
                        if [ "\${http_code}" = "200" ]; then
                          echo ""
                          echo "✅ Pyxis stage is operational!"
                          exit 0
                        fi
                        
                        attempt=\$((attempt + 1))
                        if [ \$attempt -le \$max_retries ]; then
                          echo "   Retrying in \${retry_delay}s..."
                          sleep \$retry_delay
                        fi
                      done
                      
          echo ""
          echo "❌ Pyxis stage is unavailable (HTTP \${http_code}) after 3 attempts"
          exit 1
        volumeMounts:
        - name: pyxis-secret
          mountPath: /etc/pyxis
          readOnly: true
        - name: trusted-ca
          mountPath: /mnt/trusted-ca
          readOnly: true
      volumes:
      - name: pyxis-secret
        secret:
          secretName: ${pyxis_secret_name}
      - name: trusted-ca
        configMap:
          name: trusted-ca
          items:
          - key: ca-bundle.crt
            path: ca-bundle.crt
          optional: true
EOF
            then
                job_created=true
                echo "✅ Job created successfully"
                
                # Check for FailedCreate events
                sleep 2
                local failed_create
                failed_create=$(kubectl get events -n ${managed_namespace} --field-selector involvedObject.name=${job_name},reason=FailedCreate -o jsonpath='{.items[0].message}' 2>/dev/null)
                
                if [ -n "${failed_create}" ]; then
                    echo "⚠️  Job creation failed: ${failed_create}"
                    kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
                    job_created=false
                    if [ $job_attempt -lt $max_job_attempts ]; then
                        echo "Retrying in 3s..."
                        sleep 3
                    fi
                else
                    break
                fi
            else
                echo "⚠️  kubectl apply failed"
                if [ $job_attempt -lt $max_job_attempts ]; then
                    echo "Retrying in 3s..."
                    sleep 3
                fi
            fi
        done
        
        if [ "$job_created" = "false" ]; then
            echo "❌ ERROR: Failed to create verification Job after $max_job_attempts attempts"
            log_error "Could not create Pyxis verification Job in cluster"
        fi
        
        # Wait for Pod to start (max 60s, increased from 30s)
        echo "Waiting for verification Pod to start..."
        local wait_count=0
        local pod_name=""
        while [ $wait_count -lt 60 ]; do
            pod_name=$(kubectl get pods -n ${managed_namespace} -l job-name=${job_name} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [ -n "${pod_name}" ]; then
                break
            fi
            sleep 1
            wait_count=$((wait_count + 1))
        done
        
        if [ -z "${pod_name}" ]; then
            kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
            echo "❌ ERROR: Verification Pod did not start within 60s"
            log_error "Pyxis pre-flight check failed: Pod not created"
        fi
    
    echo "✅ Verification Pod started: ${pod_name}"
    
    # Check for Pod startup failures
    local pod_phase
    pod_phase=$(kubectl get pod ${pod_name} -n ${managed_namespace} -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "${pod_phase}" = "Failed" ]; then
        echo "❌ ERROR: Verification Pod failed to start"
        kubectl describe pod ${pod_name} -n ${managed_namespace} | grep -A 10 "Events:"
        kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
        log_error "Pyxis pre-flight check failed: Pod startup failure"
    fi
    
    # Wait for Job to complete (max 120s: activeDeadlineSeconds)
    echo "Running verification checks..."
    if ! kubectl wait --for=condition=complete job/${job_name} -n ${managed_namespace} --timeout=120s 2>/dev/null; then
        echo "⚠️  Job did not complete in time, checking status..."
    fi
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    kubectl logs ${pod_name} -n ${managed_namespace} 2>/dev/null || echo "(no logs available)"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    
    # Check Job final status
    local job_succeeded
    job_succeeded=$(kubectl get job ${job_name} -n ${managed_namespace} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    local job_failed
    job_failed=$(kubectl get job ${job_name} -n ${managed_namespace} -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
    
    # Cleanup
    kubectl delete job ${job_name} -n ${managed_namespace} >/dev/null 2>&1 || true
    
    if [ "${job_succeeded}" = "True" ]; then
        echo "✅ Pyxis is operational from cluster"
        echo ""
        return 0
    elif [ "${job_failed}" = "True" ]; then
        echo "❌ Pyxis verification Job failed"
        echo ""
        echo "This idempotency test REQUIRES Pyxis stage to be operational:"
        echo "  • First release: Must write image metadata to Pyxis"
        echo "  • Second release: Must query Pyxis for idempotency verification"
        echo ""
        log_error "Pyxis stage is unavailable. Idempotency test cannot proceed."
    else
        echo "❌ Pyxis verification Job timed out or did not complete"
        echo ""
        log_error "Pyxis pre-flight check did not complete. Cannot proceed."
    fi
}

# Verify that create-pyxis-image task succeeded in first release
# Args: $1 = release name
# Returns: 0 if succeeded, 1 if failed
verify_pyxis_write_succeeded() {
    local release_name="$1"
    
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Verifying Pyxis Write (create-pyxis-image task)"
    echo "════════════════════════════════════════════════════════════════════"
    
    local pipelinerun_name
    pipelinerun_name=$(get_pipelinerun_name_from_release "${release_name}") || {
        echo "⚠️  Warning: Could not get PipelineRun name"
        return 0  # Don't fail test, just warn
    }
    
    echo "PipelineRun: ${pipelinerun_name}"
    
    # Get create-pyxis-image TaskRun status
    local taskrun_status
    taskrun_status=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=create-pyxis-image" \
        -o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null)
    
    if [ -z "${taskrun_status}" ]; then
        echo "⚠️  Warning: create-pyxis-image task not found (may have been skipped)"
        echo "This is unexpected - task should run for first release"
        return 0  # Don't block, polling will reveal the truth
    fi
    
    echo "create-pyxis-image status: ${taskrun_status}"
    
    # Check for retries
    local retry_count
    retry_count=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=create-pyxis-image" \
        -o jsonpath='{.items[0].status.retriesStatus}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    
    if [ -n "${retry_count}" ] && [ "${retry_count}" -gt 0 ] 2>/dev/null; then
        echo "⚠️  Task had ${retry_count} retries (Pyxis was flaky)"
    fi
    
    if [ "${taskrun_status}" != "Succeeded" ]; then
        echo ""
        echo "❌ CRITICAL: create-pyxis-image task status: ${taskrun_status}"
        echo ""
        echo "This means the first release did NOT write to Pyxis!"
        echo "Root cause: Pyxis was unavailable during first release execution"
        echo ""
        echo "The idempotency test will fail because:"
        echo "  • First release: No data written to Pyxis"
        echo "  • Second release: Queries Pyxis → finds nothing → pushes again"
        echo ""
        echo "This is NOT a propagation delay - it's a write failure."
        echo ""
        
        # Show task logs for debugging
        local taskrun_name
        taskrun_name=$(kubectl get taskrun -n "${managed_namespace}" \
            -l "tekton.dev/pipelineRun=${pipelinerun_name},tekton.dev/pipelineTask=create-pyxis-image" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "${taskrun_name}" ]; then
            echo "TaskRun logs (last 50 lines):"
            kubectl logs -n "${managed_namespace}" "${taskrun_name}" --tail=50 2>/dev/null || echo "(no logs available)"
        fi
        
        echo ""
        log_error "First release failed to write to Pyxis. Cannot test idempotency."
    fi
    
    echo "✅ create-pyxis-image task succeeded (Pyxis write completed)"
    echo ""
    return 0
}

# Poll Pyxis until the image digest appears (or timeout) by running a Job in the cluster
# This avoids local SSL/CA bundle issues and polls from the same network as pipeline tasks
# STRATEGY: Try repository-based query first (faster indexing), fall back to digest query
# Args: $1 = managed namespace, $2 = component name, $3 = image digest
# Returns: 0 if found, 1 if timeout
wait_for_pyxis_indexing_from_cluster() {
    local managed_namespace="$1"
    local component_name="$2"
    local digest="$3"
    local max_wait_seconds="${IDEMPOTENT_WAIT_SECONDS:-300}"
    local pyxis_secret_name="pyxis-${component_name}"
    local job_name="pyxis-poll-${uuid}"
    
    # The Pyxis repositories.repository field uses the short path form of the registry URL.
    # E.g. quay.io/redhat-pending/rhtap----rh-advisories-component → rhtap/rh-advisories-component
    # (Confirmed by inspecting actual Pyxis stage records, March 2026)
    local repository_name="rhtap/rh-advisories-component"
    
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Polling Pyxis for Image Indexing (from cluster)"
    echo "════════════════════════════════════════════════════════════════════"
    echo "Image digest: ${digest}"
    echo "Repository: ${repository_name}"
    echo "Max wait time: ${max_wait_seconds}s"
    echo "Poll interval: 15s"
    echo ""
    echo "Strategy: Try repository query first (faster), fall back to digest query"
    echo ""
    
    # URL-encode both filters (use image_id to match filter task and Pyxis API)
    local digest_filter="image_id==${digest}"
    local repo_filter="repositories.repository==${repository_name}"
    
    local digest_filter_encoded
    local repo_filter_encoded
    digest_filter_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${digest_filter}', safe=''))" 2>/dev/null)
    repo_filter_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${repo_filter}', safe=''))" 2>/dev/null)
    
    if [ -z "${digest_filter_encoded}" ] || [ -z "${repo_filter_encoded}" ]; then
        echo "⚠️  Warning: Could not URL-encode filters. Using fixed wait."
        echo "Waiting ${max_wait_seconds}s for Pyxis propagation..."
        sleep "${max_wait_seconds}"
        return 0
    fi
    
    local max_job_attempts=2
    local job_attempt=0
    local job_created=false
    
    while [ $job_attempt -lt $max_job_attempts ]; do
        job_attempt=$((job_attempt + 1))
        echo "Creating polling Job (attempt $job_attempt/$max_job_attempts)..."
        
        # Create Job that polls Pyxis FROM the cluster
        if cat <<EOF | kubectl apply -f - 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${managed_namespace}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 0
  activeDeadlineSeconds: $((max_wait_seconds + 60))
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: poll
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          set +e
          
          # Verify credentials exist
          if [ ! -f /etc/pyxis/cert ] || [ ! -f /etc/pyxis/key ]; then
            echo "❌ ERROR: Pyxis credentials not mounted"
            exit 1
          fi
          
          echo "════════════════════════════════════════════════════════════════════"
          echo "Polling Pyxis from cluster network"
          echo "════════════════════════════════════════════════════════════════════"
          echo "Digest: ${digest}"
          echo "Repository: ${repository_name}"
          echo ""
          
          # Configure CA bundle
          if [ -f /mnt/trusted-ca/ca-bundle.crt ]; then
            CA_ARGS="--cacert /mnt/trusted-ca/ca-bundle.crt"
          else
            CA_ARGS=""
          fi
          
          max_wait=${max_wait_seconds}
          poll_interval=15
          elapsed=0
          pyxis_base_url="https://pyxis.preprod.api.redhat.com/v1/images"
          
          # Query function - checks if image found with complete RPM data.
          # For image_id queries: also requires rpm_manifest.rpms to be non-empty,
          # matching the filter task's completeness check (push-rpm-data-to-pyxis done).
          # For repository queries: any image in the repo is enough (existence check).
          check_image() {
            local query_name="\$1"
            local query_url="\$2"
            local require_rpms="\${3:-false}"

            local response=\$(mktemp)
            local http_code
            http_code=\$(curl -s -o "\$response" -w "%{http_code}" --max-time 15 \
              \$CA_ARGS --cert /etc/pyxis/cert --key /etc/pyxis/key "\${query_url}" 2>/dev/null || echo "000")

            if [ "\${http_code}" != "200" ]; then
              echo "  ⏳ \${query_name}: Not yet (HTTP \${http_code})"
              rm -f "\$response"
              return 1
            fi

            local image_count
            image_count=\$(cat "\$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")

            if [ "\${image_count}" -lt 1 ] 2>/dev/null; then
              echo "  ⏳ \${query_name}: Not yet (no records)"
              rm -f "\$response"
              return 1
            fi

            if [ "\${require_rpms}" = "true" ]; then
              local rpm_count
              rpm_count=\$(cat "\$response" | python3 -c "import sys, json; d=json.load(sys.stdin); rpms=(d.get('data') or [{}])[0].get('rpm_manifest',{}).get('rpms') or []; print(len(rpms))" 2>/dev/null || echo "0")
              if [ "\${rpm_count}" -lt 1 ] 2>/dev/null; then
                echo "  ⏳ \${query_name}: Image found but rpm_manifest.rpms empty (push-rpm-data-to-pyxis pending)"
                rm -f "\$response"
                return 1
              fi
              echo "  ✅ \${query_name}: Found with RPM data (\${rpm_count} rpms)!"
            else
              echo "  ✅ \${query_name}: Found!"
            fi
            rm -f "\$response"
            return 0
          }
          
          while [ \$elapsed -lt \$max_wait ]; do
            echo ""
            echo "[\${elapsed}s / \${max_wait}s] Checking Pyxis..."

            # Primary: image_id query with RPM data check
            # Mirrors exactly what the filter task requires: image found AND rpm_manifest.rpms non-empty
            if check_image "image_id query (with RPM data)" "\${pyxis_base_url}?filter=${digest_filter_encoded}" "true"; then
              echo ""
              echo "✅ Image IS in Pyxis (found via image_id) with RPM data — filter task will skip this component"
              exit 0
            fi

            # Fallback: repository query (existence only — useful if rpm_manifest write is lagging)
            if check_image "Repository query (existence)" "\${pyxis_base_url}?filter=${repo_filter_encoded}&page_size=50" "false"; then
              echo ""
              echo "⚠️  Image found in repository but rpm_manifest.rpms not yet populated — continuing to wait"
            fi
            
            sleep \$poll_interval
            elapsed=\$((elapsed + poll_interval))
          done
          
          echo ""
          echo "❌ TIMEOUT: Image not indexed after \${max_wait}s"
          echo ""
          echo "Tried both:"
          echo "  1. image_id query (primary):  image_id==${digest} + rpm_manifest.rpms non-empty"
          echo "  2. Repository query (fallback): repositories.repository==${repository_name}"
          echo ""
          echo "After \$((max_wait / poll_interval)) poll cycles (every \${poll_interval}s)"
          echo ""
          echo "Possible causes:"
          echo "  • Pyxis stage indexing is delayed (wait longer with IDEMPOTENT_WAIT_SECONDS)"
          echo "  • Image write to Pyxis failed"
          echo "  • Pyxis stage has a systemic issue"
          exit 1
        volumeMounts:
        - name: pyxis-secret
          mountPath: /etc/pyxis
          readOnly: true
        - name: trusted-ca
          mountPath: /mnt/trusted-ca
          readOnly: true
      volumes:
      - name: pyxis-secret
        secret:
          secretName: ${pyxis_secret_name}
      - name: trusted-ca
        configMap:
          name: trusted-ca
          items:
          - key: ca-bundle.crt
            path: ca-bundle.crt
          optional: true
EOF
        then
            job_created=true
            
            # Check for FailedCreate events
            sleep 2
            local failed_create
            failed_create=$(kubectl get events -n ${managed_namespace} --field-selector involvedObject.name=${job_name},reason=FailedCreate -o jsonpath='{.items[0].message}' 2>/dev/null)
            
            if [ -n "${failed_create}" ]; then
                echo "⚠️  Job creation failed: ${failed_create}"
                kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
                job_created=false
                if [ $job_attempt -lt $max_job_attempts ]; then
                    echo "Retrying in 3s..."
                    sleep 3
                fi
            else
                break
            fi
        else
            echo "⚠️  kubectl apply failed"
            if [ $job_attempt -lt $max_job_attempts ]; then
                echo "Retrying in 3s..."
                sleep 3
            fi
        fi
    done
    
    if [ "$job_created" = "false" ]; then
        echo "❌ ERROR: Failed to create polling Job after $max_job_attempts attempts"
        echo "⚠️  Falling back to fixed wait time: ${max_wait_seconds}s"
        sleep "${max_wait_seconds}"
        return 0
    fi
    
    # Wait for Pod to start (max 60s, increased from 30s)
    echo "Waiting for polling Pod to start..."
    local wait_count=0
    local pod_name=""
    while [ $wait_count -lt 60 ]; do
        pod_name=$(kubectl get pods -n ${managed_namespace} -l job-name=${job_name} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "${pod_name}" ]; then
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if [ -z "${pod_name}" ]; then
        echo "❌ ERROR: Polling Pod did not start within 60s"
        echo "⚠️  Falling back to fixed wait time: ${max_wait_seconds}s"
        kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
        sleep "${max_wait_seconds}"
        return 0
    fi
    
    echo "✅ Polling Pod started: ${pod_name}"
    
    # Check for Pod startup failures
    local pod_phase
    pod_phase=$(kubectl get pod ${pod_name} -n ${managed_namespace} -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "${pod_phase}" = "Failed" ]; then
        echo "❌ ERROR: Polling Pod failed to start"
        kubectl describe pod ${pod_name} -n ${managed_namespace} | grep -A 10 "Events:"
        echo "⚠️  Falling back to fixed wait time: ${max_wait_seconds}s"
        kubectl delete job ${job_name} -n ${managed_namespace} 2>/dev/null || true
        sleep "${max_wait_seconds}"
        return 0
    fi
    
    # Wait for Job to complete (max: activeDeadlineSeconds)
    local total_timeout=$((max_wait_seconds + 90))
    echo "Polling Pyxis (max ${total_timeout}s)..."
    echo ""
    
    if ! kubectl wait --for=condition=complete job/${job_name} -n ${managed_namespace} --timeout=${total_timeout}s 2>/dev/null; then
        echo "⚠️  Polling Job did not complete in time"
    fi
    
    # Check Job final status FIRST (before logs, in case ttl cleanup happens)
    local job_succeeded
    job_succeeded=$(kubectl get job ${job_name} -n ${managed_namespace} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    local job_failed
    job_failed=$(kubectl get job ${job_name} -n ${managed_namespace} -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
    
    # Get logs (Pod might be gone if ttl cleanup happened)
    echo "────────────────────────────────────────────────────────────────────"
    if kubectl get pod ${pod_name} -n ${managed_namespace} &>/dev/null; then
        kubectl logs ${pod_name} -n ${managed_namespace} 2>/dev/null || echo "(no logs available)"
    else
        echo "(no logs available - Pod already cleaned up by ttlSecondsAfterFinished)"
        if [ "${job_failed}" = "True" ]; then
            echo ""
            echo "Job failed. Reason:"
            kubectl get job ${job_name} -n ${managed_namespace} -o jsonpath='{.status.conditions[?(@.type=="Failed")].message}' 2>/dev/null || echo "(unknown)"
        fi
    fi
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    
    # Cleanup
    kubectl delete job ${job_name} -n ${managed_namespace} >/dev/null 2>&1 || true
    
    if [ "${job_succeeded}" = "True" ]; then
        echo "✅ Image indexed in Pyxis"
        echo ""
        return 0
    elif [ "${job_failed}" = "True" ]; then
        echo "❌ Pyxis indexing timeout (>${max_wait_seconds}s)"
        echo ""
        echo "Increase wait time: export IDEMPOTENT_WAIT_SECONDS=300"
        echo ""
        return 1
    else
        echo "❌ Pyxis polling Job timed out or did not complete"
        echo ""
        return 1
    fi
}

verify_release_contents() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 1: First Release Verification"
    echo "════════════════════════════════════════════════════════════════════"
    
    # Note: Pre-flight check already ran in test_setup() before test started
    # Pyxis availability was verified from the cluster

    local first_release_name
    first_release_name=$(echo "${RELEASE_NAMES}" | awk '{print $1}')

    echo "First release: ${first_release_name}"

    echo "Checking if first release pushed components..."
    if were_all_components_filtered "${first_release_name}"; then
        log_error "First release should NOT have filtered components, but push-snapshot was skipped"
    fi
    echo "✅ First release pushed components (expected behavior)"

    if ! verify_single_release "${first_release_name}"; then
        log_error "First release verification failed"
    fi
    
    # CRITICAL: Verify that create-pyxis-image task actually succeeded
    # If it failed, the first release didn't write to Pyxis, making idempotency test invalid
    verify_pyxis_write_succeeded "${first_release_name}"

    local first_release_json
    first_release_json=$(get_release_json "${first_release_name}")
    local snapshot_name
    snapshot_name=$(jq -r '.spec.snapshot' <<< "${first_release_json}")

    if [ -z "${snapshot_name}" ] || [ "${snapshot_name}" == "null" ]; then
        log_error "Could not get snapshot name from first release"
    fi
    echo "Using snapshot: ${snapshot_name}"
    
    # Extract ALL image digests for Pyxis polling (supports multi-component snapshots)
    local all_image_digests
    all_image_digests=$(jq -r '.status.artifacts.images[]?.shasum // empty' <<< "${first_release_json}")

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 2: Second Release (Idempotent)"
    echo "════════════════════════════════════════════════════════════════════"

    # Poll Pyxis for every image in the snapshot (not just index 0).
    # This ensures all components in multi-component snapshots are fully indexed
    # before the second release's filter task runs.
    if [ -z "${all_image_digests}" ]; then
        local wait_seconds="${IDEMPOTENT_WAIT_SECONDS:-300}"
        echo "⚠️  Could not extract any image digests, using fixed wait time (${wait_seconds}s)"
        sleep "${wait_seconds}"
    else
        local idx=0
        while IFS= read -r image_digest; do
            [ -z "${image_digest}" ] || [ "${image_digest}" == "null" ] && continue
            idx=$(( idx + 1 ))
            echo "Polling Pyxis for image ${idx}: ${image_digest}"
            local pyxis_poll_digest
            pyxis_poll_digest=$(resolve_pyxis_poll_digest "${image_digest}" "${snapshot_name}")
            if [ -n "${pyxis_poll_digest}" ] && [ "${pyxis_poll_digest}" != "null" ]; then
                if ! wait_for_pyxis_indexing_from_cluster \
                    "${managed_namespace}" "${component_name}" "${pyxis_poll_digest}"; then
                    echo "⚠️  Pyxis polling timed out for image ${idx} — proceeding anyway."
                fi
            fi
        done <<< "${all_image_digests}"
    fi

    local second_release_name="idempotent-retry-${uuid}"
    echo "Creating second release: ${second_release_name}"

    cat <<EOF | kubectl apply -f -
apiVersion: appstudio.redhat.com/v1alpha1
kind: Release
metadata:
  name: ${second_release_name}
  namespace: ${tenant_namespace}
  labels:
    originating-tool: "${originating_tool}"
    test-type: "idempotent-second-release"
spec:
  snapshot: ${snapshot_name}
  releasePlan: ${release_plan_name}
EOF

    echo "Waiting for second release to complete..."
    export RELEASE_NAME="${second_release_name}"
    export RELEASE_NAMESPACE="${tenant_namespace}"
    "${SUITE_DIR}/../scripts/wait-for-release.sh"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Idempotent Release Test - Phase 3: Idempotent Behavior Verification"
    echo "════════════════════════════════════════════════════════════════════"

    # Get the second release's pipelinerun for detailed debugging
    local second_pipelinerun_name
    second_pipelinerun_name=$(get_pipelinerun_name_from_release "${second_release_name}")
    
    echo ""
    echo "🔍 DEBUG: Second Release PipelineRun Details"
    echo "   Release: ${second_release_name}"
    echo "   PipelineRun: ${second_pipelinerun_name}"
    echo ""
    
    # Show pipelinerun status
    echo "📊 PipelineRun Status:"
    kubectl get pipelinerun "${second_pipelinerun_name}" -n "${managed_namespace}" -o json | jq '{
        status: .status.conditions[0].reason,
        message: .status.conditions[0].message,
        skippedTasks: [.status.skippedTasks[]?.name],
        childReferences: [.status.childReferences[]? | {name: .name, pipelineTaskName: .pipelineTaskName}]
    }'
    
    # Show skipped tasks explicitly
    echo ""
    echo "📋 Skipped Tasks:"
    kubectl get pipelinerun "${second_pipelinerun_name}" -n "${managed_namespace}" \
        -o jsonpath='{range .status.skippedTasks[*]}{.name}{"\n"}{end}' || echo "  (none)"
    
    # Check filter task logs
    echo ""
    echo "🔍 Filter Task Logs (filter-already-released-by-pyxis-and-file-updates):"
    local filter_taskrun
    filter_taskrun=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${second_pipelinerun_name}" \
        -l "tekton.dev/pipelineTask=filter-already-released-by-pyxis-and-file-updates" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || filter_taskrun=""
    
    if [ -n "${filter_taskrun}" ]; then
        echo "   TaskRun: ${filter_taskrun}"
        echo ""
        echo "   Filter logs (last 100 lines):"
        kubectl logs -n "${managed_namespace}" -l "tekton.dev/taskRun=${filter_taskrun}" -c step-filter-already-released-by-metadata --tail=100 2>/dev/null || echo "   (no logs available)"
    else
        echo "   ⚠️  No filter TaskRun found"
    fi
    
    # Check if push-snapshot ran — use skippedTasks (authoritative) AND TaskRun existence (informational)
    echo ""
    echo "🔍 Push-Snapshot Task Status:"
    local push_taskrun push_skipped
    push_taskrun=$(kubectl get taskrun -n "${managed_namespace}" \
        -l "tekton.dev/pipelineRun=${second_pipelinerun_name}" \
        -l "tekton.dev/pipelineTask=push-snapshot" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || push_taskrun=""
    push_skipped=$(kubectl get pipelinerun "${second_pipelinerun_name}" -n "${managed_namespace}" \
        -o jsonpath="{.status.skippedTasks[?(@.name=='push-snapshot')].name}" 2>/dev/null || echo "")

    if [ -n "${push_skipped}" ]; then
        echo "   ✅ push-snapshot is in skippedTasks (task was correctly skipped)"
        if [ -n "${push_taskrun}" ]; then
            echo "   ⚠️  A TaskRun (${push_taskrun}) exists but task is marked skipped."
            echo "      This can happen if the release had a prior failed attempt where push-snapshot ran."
            echo "      The current PipelineRun (${second_pipelinerun_name}) correctly skipped it."
        fi
    else
        if [ -n "${push_taskrun}" ]; then
            echo "   ❌ push-snapshot TaskRun EXISTS: ${push_taskrun}"
            echo "   This indicates the task was NOT skipped (idempotency failed)"
        else
            echo "   ✅ No push-snapshot TaskRun found and not in skippedTasks (unusual state)"
        fi
    fi

    echo ""
    echo "Checking if second release filtered all components..."
    # Use second_pipelinerun_name (already resolved) for consistency — avoids stale re-lookup
    if is_task_skipped_in_plr "${second_pipelinerun_name}" "push-snapshot"; then
        echo "✅ Second release filtered all components (idempotent behavior confirmed)"
    else
        echo ""
        echo "🔴 Debug: Filter failed to skip push-snapshot. To investigate:"
        echo "  Run with: ./integration-tests/run-test.sh rh-push-to-registry-redhat-io-idempotent --skip-cleanup"
        echo "  Then inspect the filter TaskRun logs for the second release's PipelineRun:"
        echo "    kubectl get pipelinerun -n ${managed_namespace} -l \"release.appstudio.openshift.io/release=${second_release_name}\""
        echo "    kubectl get taskrun -n ${managed_namespace} -l \"tekton.dev/pipelineRun=<pipelinerun-name>\" -l \"tekton.dev/pipelineTask=filter-already-released-by-pyxis-and-file-updates\" -o name"
        echo "    kubectl logs -n ${managed_namespace} -l tekton.dev/taskRun=<filter-taskrun-name> -c step-filter-already-released-by-metadata --tail=100"
        echo ""
        echo "  Common causes: Pyxis stage propagation delay (try IDEMPOTENT_WAIT_SECONDS=300)"
        echo ""
        log_error "Second release should have filtered all components, but push-snapshot ran"
    fi

    echo ""
    echo "Verifying artifact consistency..."
    local second_release_json
    second_release_json=$(get_release_json "${second_release_name}")

    local artifacts_1 artifacts_2
    artifacts_1=$(jq -S '.status.artifacts.images[0].shasum // "null"' <<< "${first_release_json}")
    artifacts_2=$(jq -S '.status.artifacts.images[0]?.shasum // "null"' <<< "${second_release_json}")

    if [ "${artifacts_2}" == "\"null\"" ] || [ "${artifacts_2}" == "null" ]; then
        echo "✅ Second release has no artifacts (expected - all components filtered, push-snapshot skipped)"
        echo "   First release pushed: ${artifacts_1}"
        echo "   Second release skipped push (idempotent)"
    elif [ "${artifacts_1}" == "${artifacts_2}" ]; then
        echo "✅ Both releases report identical artifact digests"
    else
        echo "First release artifacts: ${artifacts_1}"
        echo "Second release artifacts: ${artifacts_2}"
        log_error "Releases report different artifacts: ${artifacts_1} vs ${artifacts_2}"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ✅ IDEMPOTENT RELEASE TEST PASSED (rh-push-to-registry-redhat-io)"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Summary:"
    echo "  • First release pushed 1 component (pyxis, signing)"
    echo "  • Second release filtered component (Pyxis already had image)"
    echo "  • Artifact consistency: Verified"
    echo "  • Idempotent behavior: ✅ CONFIRMED"
    echo ""
}

# Hook: resolve_pyxis_poll_digest <image_digest> <snapshot_name>
# Returns the digest to use when polling Pyxis before the second release.
# Default (single-arch): return the digest unchanged.
# Override in multi-arch sub-suites to resolve a manifest list to a per-arch digest.
resolve_pyxis_poll_digest() {
    echo "$1"
}
