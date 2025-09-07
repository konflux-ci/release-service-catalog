#!/usr/bin/env bash
set -x

# seed for the build status
yq -o json <<< '
items:
- id: 1
  distribution_scope: "stage"
  from_index: "registry-proxy-stage.engineering.redhat.com/rh-osbs/iib-pub:v4.17"
  fbc_fragments: ["registry.io/image0@sha256:0000"]
  internal_index_image_copy: "registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib:1"
  index_image_resolved: "registry-proxy-stage.engineering.redhat.com/rh-osbs-stage/iib@sha256:0000"
  index_image: "registry-proxy-stage.engineering.redhat.com/rh-osbs/iib-pub:v4.17"
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
  if [[ "$params" =~ "--negotiate -u: https://pyxis.engineering.redhat.com/v1/repositories/registry/quay.io/repository/repo/image -o"* ]]; then
    tempfile="$5"
    echo -e '{ "fbc_opt_in": true }' > "$tempfile"

  elif [[ "$params" =~ "-s https://fakeiib.host/builds?user=iib@kerberos&from_index=quay.io/scoheb/fbc-index-testing:"* ]]; then
    build="${buildSeed}"
    case "$(context.taskRun.name)" in
        *complete*|*outdated*)
          taskrun_name=$(awk '{print substr($1, index($1, "retry"))}' <<< "$(context.taskRun.name)")
          build=$(jq -rc --arg taskrun_name "$taskrun_name" '.items[0].mock_case = $taskrun_name' <<< "${build}")
          build=$(jq -rc '.items[0].state = "complete"' <<< "${build}")
          build=$(jq -rc '.items[0].state_reason = "The FBC fragment was successfully added in the index image"' <<< "${build}")
        ;;
        *"retry-in-progress"*)
          build=$(jq -rc '.items[0].mock_case = "retry-in-progress"' <<< "${buildSeed}")
        ;;
        *empty-fragments*)
          # For empty fragments test, the task should exit early before reaching this point
          # But if it does reach here, return empty build list
          build='{"items": []}'
        ;;
    esac
    echo -en "${build}"

  elif [[ "$params" == "-s https://fakeiib.host/builds/1" ]]; then
    set -x
    echo "$*" >> mock_build_progress_calls
    if [[ "$(context.taskRun.name)" =~ "test-update-fbc-catalog-error"* ]]; then
        mock_error="true"
    fi

    # Decompress the jsonBuildInfo since task now uses compression
    buildJson="$(base64 -d < $(results.jsonBuildInfo.path) | gunzip)"
    mock_build_progress "$(awk 'END{ print NR }' mock_build_progress_calls)" "$(base64 <<< "${buildJson}")" "$mock_error" | tee build_json
    export -n buildJson
    buildJson=$(cat build_json)
    export buildJson

  elif [[ "$params" == "-s https://fakeiib.host/api/v1/builds/1/logs" ]]; then
    echo "Logs are for weaks"

  elif [[ "$params" =~ "-u : --negotiate -s -X POST -H Content-Type: application/json -d@".*" --insecure https://fakeiib.host/builds/fbc-operations" ]]; then
    # For multiple fragments tests, update the buildJson to include the appropriate fbc_fragments array
    case "$(context.taskRun.name)" in
        *multiple-fragments*)
          if [[ "$(context.taskRun.name)" =~ "multiple-fragments-retry" ]]; then
            # For retry scenario with 2 fragments
            buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111"]' <<< "${buildJson}")
          else
            # For basic multiple fragments test with 3 fragments
            buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000", "registry.io/image1@sha256:1111", "registry.io/image2@sha256:2222"]' <<< "${buildJson}")
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
        *error*)
          # For error test - return successful API response, but build will fail in step 2
          buildJson=$(jq -c '.fbc_fragments = ["registry.io/image0@sha256:0000"]' <<< "${buildJson}")
        ;;
    esac
    # Export the updated buildJson for use in subsequent calls
    export buildJson
    # Compress the output since task expects compressed results
    echo "${buildJson}" | gzip -c | base64 -w0
  else
    echo ""
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

    if [[ "$*" == "--retry-times 3 --config docker://quay.io/fbc/catalog:complete" ]]; then
        echo '{"created": "'"${yesterday}"'"}'
    fi

    if [[ "$*" == "--retry-times 3 --config docker://quay.io/fbc/catalog:outdated" ]]; then
        echo '{"created": "'"${tomorrow}"'"}'
    fi
}

# the watch_build_state can't reach some mocks by default, so exporting them fixes it.
export -f curl
export -f mock_build_progress

# The retry script won't see the kinit function unless we export it
export -f kinit
