#!/usr/bin/env bash
set -x

echo "CLAUDE_DEBUGGING: mocks.sh file loaded successfully with fix attempt $(date)" >&2

# seed for the build status
yq -o json <<< '
items:
- id: 1
  distribution_scope: "stage"
  from_index: "quay.io/scoheb/fbc-index-testing:latest"
  fbc_fragments: ["registry.io/image0@sha256:0000"]
  build_tags: ["v4.12", "hotfix"]
  internal_index_image_copy: "registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib:1"
  index_image_resolved: "registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib@sha256:0000"
  index_image: "quay.io/scoheb/fbc-index-testing:latest"
  logs:
    url: "https://fakeiib.host/api/v1/builds/1/logs"
  request_type: "fbc-operations"
  state: "in_progress"
  state_reason: "The request was initiated"
  state_history:
    - state: "in_progress"
      state_reason: "The request was initiated"
  user: "iib@kerberos"' > /tmp/build-seed

buildSeed=$(cat /tmp/build-seed)
buildJson=$(jq -cr '.items[0]' <<< "${buildSeed}")

export buildSeed buildJson calls

# Helper function to generate jq expression for auth-failure test build
# Takes timestamp as parameter and returns jq expression string
get_auth_failure_jq_expr() {
  local timestamp="$1"
  echo '.items[0] |= (.fbc_fragments = ["registry.io/image0@sha256:0000"] | .from_index = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" | .from_index_resolved = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub@sha256:3d6fe02b28ab876d60af3c3df5100a6fe4c99b084651af547659173d680c6f4d" | .index_image = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" | .index_image_resolved = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub@sha256:10b1d5b1d053d8c3a2263201baa983c760e6b61f3a50e3cde244fdaf68a4aed9" | .updated = "'"${timestamp}"'" | .state = "complete" | .state_reason = "The FBC fragment was successfully added in the index image")'
}

function mock_build_progress() {

    state_reason[1]="Resolving the fbc fragment"
    state_reason[2]="Resolving the container images"
    state_reason[3]="The FBC fragment was successfully added in the index image"

    encoded_script="$2"
    calls="$1"
    mock_error="$3"

    build="$(base64 -d <<< "$encoded_script")"
    if [ -n "$mock_error" ]; then
        build=$(jq -rc '.state |= "failed"' <<< "$build")
        build=$(jq -rc '.state_reason |= "IIB Mocked Error"' <<< "${build}")
        build=$(jq -rc --argjson progress "{ \"state\": \"failed\", \"state_reason\": \"IIB Mocked Error\" }" '.state_history |= [$progress] + .' <<< "${build}")
        echo "${build}"
        return
    fi

    if [ "$calls" -gt "${#state_reason[@]}" ]; then
        jq -cr . <<< "${build}"
    elif [ "$calls" -eq "${#state_reason[@]}" ]; then
        build=$(jq -rc '.state |= "complete"' <<< "$build")
        build=$(jq -rc '.state_reason |= "The FBC fragment was successfully added in the index image"' <<< "${build}")
        # Preserve fbc_fragments field from the build data instead of using defaults
        build=$(jq -rc --argjson progress "{ \"state\": \"complete\", \"state_reason\": \"${state_reason[$calls]}\" }" '.state_history |= [$progress] + .' <<< "${build}")
        # Ensure empty fragments tests have empty fbc_fragments in final result
        echo "${build}"
        return
    else
        jq -rc --argjson progress "{ \"state\": \"in_progress\", \"state_reason\": \"${state_reason[$calls]}\" }" '.state_history |= [$progress] + .' <<< "${build}"
    fi
}

function curl() {
  params="$*"
  # Debug: always print the task name and curl params for troubleshooting
  echo "DEBUG: TaskRun name: $(context.taskRun.name)" >&2
  echo "DEBUG: curl params: $params" >&2
  
  if [[ "$params" =~ "--negotiate -u: https://pyxis.engineering.redhat.com/v1/repositories/registry/quay.io/repository/repo/image -o"* ]]; then
    tempfile="$5"
    echo -e '{ "fbc_opt_in": true }' > "$tempfile"

  elif [[ "$params" == *"-s https://fakeiib.host/builds"* ]] && [[ "$params" == *"from_index="* ]] && [[ "$params" == *"state="* ]] && [[ "$params" != *"/builds/1"* ]] && [[ "$params" != *"/api/v1/builds"* ]]; then
    # Check params directly for registry-proxy pattern (most reliable)
    is_registry_proxy_test=false
    if [[ "$params" =~ registry-proxy.engineering.redhat.com/rh-osbs/iib-pub ]]; then
      is_registry_proxy_test=true
    fi
    # Extract from_index from params to help with debugging
    # Handle both URL-encoded and non-encoded versions
    extracted_from_index=""
    # Try multiple patterns to extract from_index
    # Expected formats in params:
    #   - Non-encoded: "from_index=registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12"
    #   - URL-encoded: "from_index%3Dregistry-proxy.engineering.redhat.com%2Frh-osbs%2Fiib-pub%3Av4.12"
    #   (where %3D is '=', %2F is '/', %3A is ':')
    if [[ "$params" =~ from_index=([^&\ ]+) ]]; then
      extracted_from_index="${BASH_REMATCH[1]}"
    elif [[ "$params" =~ from_index%3D([^&\ ]+) ]]; then
      # URL-encoded equals sign (%3D = '=')
      extracted_from_index="${BASH_REMATCH[1]}"
    fi
    # URL decode if needed (simple case for common characters)
    if [[ -n "$extracted_from_index" ]]; then
      extracted_from_index="${extracted_from_index//%3A/:}"
      extracted_from_index="${extracted_from_index//%2F//}"
      extracted_from_index="${extracted_from_index//%40/@}"
      # If from_index contains registry-proxy, we should be in auth-failure test
      if [[ "$extracted_from_index" =~ registry-proxy.engineering.redhat.com/rh-osbs/iib-pub ]]; then
        is_registry_proxy_test=true
      fi
    fi
    build="${buildSeed}"
    taskrun_name="$(context.taskRun.name)"
    
    # Check if this is the auth-failure test by from_index value FIRST (more reliable)
    # If from_index contains registry-proxy, treat it as auth-failure regardless of taskrun name
    # For auth-failure test: return an OLD build (>24 hours) that should be rejected
    if [[ "$is_registry_proxy_test" = "true" ]] || \
       ([[ -n "$extracted_from_index" ]] && [[ "$extracted_from_index" =~ registry-proxy.engineering.redhat.com/rh-osbs/iib-pub ]]); then
      # Set updated timestamp to 25 hours ago (old build that should be rejected)
      old_timestamp=$(date -u -d '25 hours ago' --iso-8601=seconds 2>/dev/null || date -u -v-25H --iso-8601=seconds 2>/dev/null || echo "$(date -u --iso-8601=seconds)")
      jq_expr="$(get_auth_failure_jq_expr "${old_timestamp}")"
      build=$(jq -rc "$jq_expr" <<< "${build}")
    else
      # Fall back to taskrun name matching
      case "${taskrun_name}" in
        *auth-failure*)
          # For auth-failure test, return an OLD build (>24 hours) that should be rejected
          # Check this BEFORE *complete* to avoid pattern collision
          old_timestamp=$(date -u -d '25 hours ago' --iso-8601=seconds 2>/dev/null || date -u -v-25H --iso-8601=seconds 2>/dev/null || echo "$(date -u --iso-8601=seconds)")
          jq_expr="$(get_auth_failure_jq_expr "${old_timestamp}")"
          build=$(jq -rc "$jq_expr" <<< "${build}")
        ;;
        *complete*|*multiple-fragments-retry*|*multiple-fragments*)
          # For complete and multiple-fragments-retry tests, use "retry-complete" as the mock case
          # Added *multiple-fragments* to catch truncated names
          taskrun_name="retry-complete"
          echo "DEBUG: Setting retry-complete case" >&2
          # For multiple fragments retry test, set the correct fragments array to match what the task expects
          if [[ "$(context.taskRun.name)" =~ "multiple-fragments-retry" ]]; then
            # Retry scenario with 2 fragments, ensure from_index and index_image match task parameters
            build=$(jq -rc '.items[0].fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111"] | .items[0].from_index = "quay.io/scoheb/fbc-index-testing:latest" | .items[0].index_image = "quay.io/scoheb/fbc-index-testing:latest"' <<< "${build}")
          elif [[ "$(context.taskRun.name)" =~ "multiple-fragments" ]]; then
            # Basic multiple fragments test with 3 fragments, ensure from_index and index_image match task parameters
            build=$(jq -rc '.items[0].fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111", "registry.io/image2@sha256:2222"] | .items[0].from_index = "quay.io/scoheb/fbc-index-testing:latest" | .items[0].index_image = "quay.io/scoheb/fbc-index-testing:latest"' <<< "${build}")
          fi
          build=$(jq -rc --arg taskrun_name "$taskrun_name" '.items[0].mock_case = $taskrun_name' <<< "${build}")
          build=$(jq -rc '.items[0].state = "complete"' <<< "${build}")
          build=$(jq -rc '.items[0].state_reason = "The FBC fragment was successfully added in the index image"' <<< "${build}")
        ;;
        *outdated*)
          # For outdated tests, set state to complete but don't set mock_case (triggers new build)
          echo "DEBUG: Setting outdated case" >&2
          build=$(jq -rc '.items[0].state = "complete"' <<< "${build}")
          build=$(jq -rc '.items[0].state_reason = "The FBC fragment was successfully added in the index image"' <<< "${build}")
        ;;
        *"retry-in-progress"*)
          echo "DEBUG: Setting retry-in-progress case" >&2
          build=$(jq -rc '.items[0].mock_case = "retry-in-progress"' <<< "${buildSeed}")
        ;;
        *empty-fragments*)
          # For empty fragments test, the task should exit early before reaching this point
          # But if it does reach here, return empty build list
          echo "DEBUG: Setting empty-fragments case" >&2
          build='{"items": []}'
        ;;
        *index-mismatch*)
          # For index-mismatch test, return a completed build with wrong index_image
          echo "DEBUG: Setting index-mismatch case" >&2
          build=$(jq -rc '.items[0].fbc_fragments = ["registry.io/image0@sha256:0000"] | .items[0].from_index = "quay.io/fbc/catalog:mismatch" | .items[0].index_image = "quay.io/scoheb/fbc-index-testing:latest"' <<< "${build}")
          build=$(jq -rc '.items[0].state = "complete"' <<< "${build}")
          build=$(jq -rc '.items[0].state_reason = "The FBC fragment was successfully added in the index image"' <<< "${build}")
        ;;
        *)
          # Fallback: if from_index contains registry-proxy and we didn't match any case,
          # treat it as auth-failure test (return old build)
          if [[ -n "$extracted_from_index" ]] && [[ "$extracted_from_index" =~ registry-proxy.engineering.redhat.com/rh-osbs/iib-pub ]]; then
            old_timestamp=$(date -u -d '25 hours ago' --iso-8601=seconds 2>/dev/null || date -u -v-25H --iso-8601=seconds 2>/dev/null || echo "$(date -u --iso-8601=seconds)")
            jq_expr="$(get_auth_failure_jq_expr "${old_timestamp}")"
            build=$(jq -rc "$jq_expr" <<< "${build}")
          fi
        ;;
      esac
    fi
    
    # Final check: ALWAYS check params directly for registry-proxy pattern and fix if needed
    # This is the most reliable check - just look for the pattern in the params string
    current_from_index=$(jq -r '.items[0].from_index // empty' <<< "${build}")
    if [[ "$params" == *"registry-proxy.engineering.redhat.com/rh-osbs/iib-pub"* ]]; then
      if [[ "$current_from_index" != "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" ]]; then
        old_timestamp=$(date -u -d '25 hours ago' --iso-8601=seconds 2>/dev/null || date -u -v-25H --iso-8601=seconds 2>/dev/null || echo "$(date -u --iso-8601=seconds)")
        jq_expr="$(get_auth_failure_jq_expr "${old_timestamp}")"
        build=$(jq -rc "$jq_expr" <<< "${build}")
      fi
    fi
    echo -en "${build}"

  elif [[ "$params" == "-s https://fakeiib.host/builds/1" ]] || [[ "$params" == "-s https://fakeiib.host/builds/2" ]]; then
    set -x
    echo "$*" >> mock_build_progress_calls
    if [[ "$(context.taskRun.name)" =~ "test-update-fbc-catalog-error"* ]]; then
        mock_error="true"
    fi

    # Decompress the jsonBuildInfo since task now uses compression
    buildJson="$(base64 -d < $(results.jsonBuildInfo.path) | gunzip)"

    # For index-mismatch test, keep default index_image to trigger validation failure
    # (no action needed - default index_image won't match fromIndex)

    mock_build_progress "$(awk 'END{ print NR }' mock_build_progress_calls)" "$(base64 <<< "${buildJson}")" "$mock_error" | tee build_json
    export -n buildJson
    buildJson=$(cat build_json)
    export buildJson

  elif [[ "$params" == "-s https://fakeiib.host/api/v1/builds/1/logs" ]] || [[ "$params" == "-s https://fakeiib.host/api/v1/builds/2/logs" ]]; then
    echo "Logs are for weaks"

  elif [[ "$params" =~ "-u : --negotiate -s -X POST -H Content-Type: application/json -d@".*" --insecure https://fakeiib.host/builds/fbc-operations" ]]; then
    # For POST requests, use the buildSeed template as the base
    buildJson=$(jq -cr '.items[0]' <<< "${buildSeed}")
    
    # Check if this is auth-failure test by taskrun name
    if [[ "$(context.taskRun.name)" == *"auth-failure"* ]]; then
      # For auth-failure test, set correct from_index and assign a NEW id (2) since old build (1) was rejected
      buildJson=$(jq -c '.id = 2 | .from_index = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" | .index_image = "registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" | .logs.url = "https://fakeiib.host/api/v1/builds/2/logs"' <<< "${buildJson}")
    fi
    
    # For multiple fragments tests, update the buildJson to include the appropriate fbc_fragments array
    case "$(context.taskRun.name)" in
        *multiple-fragments*)
          if [[ "$(context.taskRun.name)" =~ "multiple-fragments-retry" ]]; then
            # For retry scenario with 2 fragments
            buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111"]' <<< "${buildJson}")
          else
            # For basic multiple fragments test with 3 fragments, set correct index_image for production build validation
            buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111", "registry.io/image2@sha256:2222"] | .index_image = "quay.io/scoheb/fbc-index-testing:latest"' <<< "${buildJson}")
          fi
        ;;
        *empty-fragments*)
          # For empty array test - this should not be reached since task exits early
          buildJson=$(jq -c '.fbc_fragments = []' <<< "${buildJson}")
        ;;
        *invalid-fragments*)
          # For invalid JSON test - this shouldn't reach here due to early validation failure
          # But if it does, return an error response
          echo '{"error": "Invalid fbc_fragments parameter"}'
          exit
        ;;
        *index-mismatch*)
          # For index-mismatch test, set up mismatched from_index and index_image
          buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000"] | .from_index = "quay.io/fbc/catalog:mismatch" | .index_image = "quay.io/scoheb/fbc-index-testing:latest"' <<< "${buildJson}")
        ;;
        *error*)
          # For error test - return successful API response, but build will fail in step 2
          buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000"]' <<< "${buildJson}")
        ;;
    esac
    # Export the updated buildJson for use in subsequent calls
    export buildJson
    # Return uncompressed JSON - the task will handle compression
    echo "${buildJson}"
  else
    # Catch-all: if no pattern matched, check if it looks like a check_previous_build call
    if [[ "$params" == *"-s https://fakeiib.host/builds"* ]] && [[ "$params" == *"from_index="* ]] && [[ "$params" == *"state="* ]] && [[ "$params" != *"/builds/1"* ]] && [[ "$params" != *"/api/v1/builds"* ]]; then
      # This should have been caught by the earlier pattern, but if not, handle it here
      build="${buildSeed}"
      if [[ "$params" == *"registry-proxy.engineering.redhat.com/rh-osbs/iib-pub"* ]]; then
        old_timestamp=$(date -u -d '25 hours ago' --iso-8601=seconds 2>/dev/null || date -u -v-25H --iso-8601=seconds 2>/dev/null || echo "$(date -u --iso-8601=seconds)")
        jq_expr="$(get_auth_failure_jq_expr "${old_timestamp}")"
        build=$(jq -rc "$jq_expr" <<< "${build}")
      fi
      echo -en "${build}"
    else
      echo ""
    fi
  fi
}

function opm() {
  # Return appropriate bundle info for any fragment image
  # The task uses this to extract bundle images for fbc_opt_in checks
  echo '{ "schema": "olm.bundle", "image": "quay.io/repo/image@sha256:abcd1234"}'
}

function base64() {
    # Only mock the keytab decryption, use real base64 for other operations
    if [[ "$*" == "-d /mnt/service-account-secret/keytab" ]]; then
        echo "decrypted-keytab"
    else
        # Use the real base64 command for all other operations
        # This preserves input redirection and pipe functionality
        command base64 "$@"
    fi
}

function kinit() {
    echo "Ok"
}

function skopeo() {
    today="$(date --iso-8601="seconds")"
    yesterday="$(date --date="yesterday" --iso-8601="seconds")"
    tomorrow="$(date --date="tomorrow" --iso-8601="seconds")"

    shift
    if [[ "$*" == "--retry-times 3 --raw docker://registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib:1" ]]; then
        echo '{"manifests": ['
        echo '{ "mediaType": "application/vnd.docker.distribution.manifest.v2+json", "digest": "sha256:000" },'
        echo '{ "mediaType": "application/vnd.docker.distribution.manifest.v2+json", "digest": "sha256:001" }'
        echo ']}'
    fi

    if [[ "$*" == "--retry-times 3 --config docker://registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib@sha256:0000" ]]; then
        echo '{"created": "'"${today}"'"}'
    fi

    # For auth-failure test: fail when inspecting from_index by tag (simulates auth error)
    if [[ "$*" =~ "--retry-times 3 --config docker://registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12" ]] && \
       [[ "$(context.taskRun.name)" =~ "auth-failure" ]]; then
        # Simulate auth failure - return error and exit with non-zero
        echo "time=\"$(date -u --iso-8601=seconds)\" level=fatal msg=\"Error parsing image name \\\"docker://registry-proxy.engineering.redhat.com/rh-osbs/iib-pub:v4.12\\\": reading manifest v4.12 in registry-proxy.engineering.redhat.com/rh-osbs/iib-pub: unauthorized: access to the requested resource is not authorized\"" >&2
        return 1
    fi

    # For auth-failure test: also fail when inspecting from_index_resolved by digest
    # This ensures freshness cannot be verified, and old build will be rejected
    if [[ "$*" =~ "--retry-times 3 --config docker://registry-proxy.engineering.redhat.com/rh-osbs/iib-pub@sha256:3d6fe02b28ab876d60af3c3df5100a6fe4c99b084651af547659173d680c6f4d" ]] && \
       [[ "$(context.taskRun.name)" =~ "auth-failure" ]]; then
        # Simulate auth failure for digest inspection too
        echo "time=\"$(date -u --iso-8601=seconds)\" level=fatal msg=\"Error parsing image name \\\"docker://registry-proxy.engineering.redhat.com/rh-osbs/iib-pub@sha256:3d6fe02b28ab876d60af3c3df5100a6fe4c99b084651af547659173d680c6f4d\\\": reading manifest sha256:3d6fe02b28ab876d60af3c3df5100a6fe4c99b084651af547659173d680c6f4d in registry-proxy.engineering.redhat.com/rh-osbs/iib-pub: unauthorized: access to the requested resource is not authorized\"" >&2
        return 1
    fi

    # For auth-failure test: succeed when inspecting index_image_resolved (always works)
    if [[ "$*" =~ "--retry-times 3 --config docker://registry-proxy.engineering.redhat.com/rh-osbs/iib-pub@sha256:10b1d5b1d053d8c3a2263201baa983c760e6b61f3a50e3cde244fdaf68a4aed9" ]] && \
       [[ "$(context.taskRun.name)" =~ "auth-failure" ]]; then
        echo '{"created": "'"${today}"'"}'
        return 0
    fi

}

# the watch_build_state can't reach some mocks by default, so exporting them fixes it.
export -f curl
export -f mock_build_progress
export -f get_auth_failure_jq_expr

# The retry script won't see the kinit function unless we export it
export -f kinit

# The second step needs the skopeo function for indexImageDigests calculation
export -f skopeo
