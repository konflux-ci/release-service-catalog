#!/usr/bin/env bash
set -x

# seed for the build status
yq -o json <<< '
items:
- id: 1
  distribution_scope: "stage"
  from_index: "registry-proxy-stage.engineering.redhat.com/rh-osbs/iib-pub:v4.17"
  fbc_fragment: "registry.io/image0@sha256:0000"
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
        jq -rc --argjson progress "{ \"state\": \"failed\", \"state_reason\": \"IIB Mocked Error\" }" '.state_history |= [$progress] + .' <<< "${build}"
        exit
    fi

    if [ "$calls" -gt "${#state_reason[@]}" ]; then
        jq -cr . <<< "${build}"
    elif [ "$calls" -eq "${#state_reason[@]}" ]; then
        build=$(jq -rc '.state |= "complete"' <<< "$build")
        build=$(jq -rc '.state_reason |= "The FBC fragment was successfully added in the index image"' <<< "${build}")
        jq -rc --argjson progress "{ \"state\": \"complete\", \"state_reason\": \"${state_reason[$calls]}\" }" '.state_history |= [$progress] + .' <<< "${build}"
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
    esac
    echo -en "${build}"

  elif [[ "$params" == "-s https://fakeiib.host/builds/1" ]]; then
    set -x
    echo "$*" >> mock_build_progress_calls
    if [[ "$(context.taskRun.name)" =~ "test-update-fbc-catalog-error"* ]]; then
        mock_error="true"
    fi

    buildJson="$(cat $(results.jsonBuildInfo.path))"
    mock_build_progress "$(awk 'END{ print NR }' mock_build_progress_calls)" "$(base64 <<< "${buildJson}")" "$mock_error" | tee build_json
    export -n buildJson
    buildJson=$(cat build_json)
    export buildJson

  elif [[ "$params" == "-s https://fakeiib.host/api/v1/builds/1/logs" ]]; then
    echo "Logs are for weaks"

  elif [[ "$params" =~ "-u : --negotiate -s -X POST -H Content-Type: application/json -d@".*" --insecure https://fakeiib.host/builds/fbc-operations" ]]; then
    echo "${buildJson}"
  else
    echo ""
  fi
}

function opm() {
  echo '{ "schema": "olm.bundle", "image": "quay.io/repo/image@sha256:abcd1234"}'
}

function base64() {
    echo "decrypted-keytab"
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
