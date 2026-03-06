#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

# Counter for generating unique hrefs
UPLOAD_COUNTER=0
# One-time failure switch for rpm content upload (controlled by image-based behavior)
UPLOAD_FAIL_ONCE_ENABLED=0
# Persisted state across subshells (command substitutions) for "fail once" behavior
UPLOAD_FAIL_ONCE_ENABLED_FILE="/tmp/mock_upload_failonce_enabled"
UPLOAD_FAIL_ONCE_DONE_FILE="/tmp/mock_upload_failonce_done"
# Control whether content queries should pretend items already exist
CONTENT_EXISTS_MODE_FILE="/tmp/mock_content_exists_mode"

function curl() {
    # Mock curl for OAuth2 and API calls
    local args="$*"

    if [[ "$args" == *"sso.redhat.com"* ]]; then
        # Record token requests (for auth-path tests). Do not record full args to avoid logging secrets.
        echo "token_request" >> ${DATA_DIR}/mock_sso.txt
        # OAuth2 token request
        echo '{"access_token": "mock-access-token", "expires_in": 3600}'
    elif [[ "$args" == *"/api/pulp/mock/api/v3/repositories/rpm/rpm/"* ]] && [[ "$args" != *"name="* ]] && [[ "$args" != *"modify"* ]]; then
        # Repository GET by href -> return latest_version_href
        echo '{"latest_version_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/mock-repo-uuid/versions/1/"}'
    elif [[ "$args" == *"/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/"* ]]; then
        # Content GET (package) by href -> return artifact link
        echo '{"pulp_href": "/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/", "artifact": "/api/pulp/mock/api/v3/artifacts/mock-artifact-uuid/"}'
    # SRPMs are queried via the packages endpoint with arch=src; no separate srpms endpoint.
    elif [[ "$args" == *"/api/pulp/mock/api/v3/artifacts/"* ]]; then
        # Artifact GET -> return sha256 of empty file
        echo '{"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}'
    elif [[ "$args" == *"/content/rpm/packages/"* ]] && [[ "$args" != *"modify"* ]]; then
        # Content query by NEVRA -> decide existence based on CONTENT_EXISTS_MODE_FILE
        mode="none"
        if [[ -f "${CONTENT_EXISTS_MODE_FILE}" ]]; then
            mode="$(cat "${CONTENT_EXISTS_MODE_FILE}")"
        fi
        # record the content query for debugging the tests
        echo "content_query mode=${mode} url=${args}" >> ${DATA_DIR}/mock_content_queries.txt
        if [[ "${mode}" == "all" ]]; then
            echo '{"count": 1, "results": [{"pulp_href": "/api/pulp/mock/api/v3/content/rpm/packages/mock-existing-uuid/", "artifact": "/api/pulp/mock/api/v3/artifacts/mock-artifact-uuid/"}]}'
        else
            echo '{"count": 0, "results": []}'
        fi
    elif [[ "$args" == *"repositories/rpm/rpm"* && "$args" == *"name="* ]]; then
        # Repository list API call - extract repo name from URL
        if [[ "$args" == *"name=source"* ]]; then
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/source-uuid/"}]}'
        elif [[ "$args" == *"name=x86_64"* ]]; then
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/x86_64-uuid/"}]}'
        elif [[ "$args" == *"name=aarch64"* ]]; then
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/aarch64-uuid/"}]}'
        elif [[ "$args" == *"name=ppc64le"* ]]; then
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/ppc64le-uuid/"}]}'
        elif [[ "$args" == *"name=s390x"* ]]; then
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/s390x-uuid/"}]}'
        else
            echo '{"results": [{"pulp_href": "/api/pulp/mock/api/v3/repositories/rpm/rpm/default-uuid/"}]}'
        fi
    elif [[ "$args" == *"modify"* ]]; then
        # Repository content modify API call (script expects body then \n%{http_code})
        echo '{"task": "/api/pulp/mock/api/v3/tasks/mock-task-id/"}'
        echo '202'
    elif [[ "$args" == *"/tasks/"* ]] && [[ "$args" != *"modify"* ]]; then
        # Task poll (GET) - return completed so wait_for_pulp_task exits
        echo '{"state": "completed"}'
    else
        # Fall back to real curl for other calls
        command curl "$@"
    fi
}

function pulp() {
    echo $* >> ${DATA_DIR}/mock_pulp.txt
    if [[ "$*" == *"domain show"* ]]; then
        echo "{ \"name\": \"mydomain\" }"
    elif [[ "$*" == *"rpm repository list"* ]]; then
        echo "[ {\"name\": \"x86_64\"}, {\"name\": \"ppc64le\"}, {\"name\": \"s390x\"}, {\"name\": \"aarch64\"}, {\"name\": \"source\"} ]"
    elif [[ "$*" == *"rpm content upload"* ]]; then
        # Optionally fail the very first upload attempt once to exercise retry logic.
        # Always prioritize the persisted "done" file to avoid re-failing across subshells.
        if [[ -f "${UPLOAD_FAIL_ONCE_DONE_FILE}" ]]; then
            :
        elif [[ -f "${UPLOAD_FAIL_ONCE_ENABLED_FILE}" || "${UPLOAD_FAIL_ONCE_ENABLED}" -eq 1 ]]; then
            echo "Error: ('Connection aborted.', ConnectionResetError(104, 'Connection reset by peer'))" >&2
            # Mark as done so subsequent attempts succeed
            touch "${UPLOAD_FAIL_ONCE_DONE_FILE}"
            return 1
        fi
        # Return JSON with pulp_href for each (successful) upload
        UPLOAD_COUNTER=$((UPLOAD_COUNTER + 1))
        echo "{\"pulp_href\": \"/api/pulp/mock/api/v3/content/rpm/packages/mock-uuid-${UPLOAD_COUNTER}/\"}"
    elif [[ "$*" == *"rpm repository content modify"* ]]; then
        # Handle bulk content add - just acknowledge
        echo "{\"task\": \"/api/pulp/mock/api/v3/tasks/mock-task-id/\"}"
    else
        echo Error: Unexpected call
        exit 1
    fi
}

function select-oci-auth() {
    echo Mock select-oci-auth called with: $*
}

function oras() {
    echo Mock oras called with: $*
    echo $* >> ${DATA_DIR}/mock_oras.txt
    local args="$*"

    if [[ "$*" == "pull --registry-config"* ]]; then
        echo "Mocking pulling files"

        # Initialize a variable to store the value of the -o flag.
        output_file_dir=""

        # Reset content-exists mode to a sane default for each pull to avoid leakage across tests
        echo "none" > "${CONTENT_EXISTS_MODE_FILE}"

        # Loop through all arguments passed to the script.
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o|--output)
                    # Check if there is a next argument to capture.
                    if [[ -n "$2" ]]; then
                        # Capture the value of the next argument and store it.
                        output_file_dir="$2"
                        # Shift twice to move past both the flag and its value.
                        shift 2
                    fi
                    ;;
                *)
                    # For any other arguments, just shift past them.
                    shift
                    ;;
            esac
        done

        # Check if the output_file variable was successfully populated.
        if [[ -n "$output_file_dir" ]]; then
            echo "The captured output file dir is: $output_file_dir"
        fi

        if [[ "$args" == *"quay.io/test/happypath-failonce"* ]]; then
            # Enable one-time failure for rpm content upload
            UPLOAD_FAIL_ONCE_ENABLED=1
            # Persist enablement and reset done flag for this container
            echo "1" > "${UPLOAD_FAIL_ONCE_ENABLED_FILE}"
            rm -f "${UPLOAD_FAIL_ONCE_DONE_FILE}"
            # For failonce, pretend content does not exist so uploads happen
            echo "none" > "${CONTENT_EXISTS_MODE_FILE}"
            touch $output_file_dir/hello-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.src.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-docs-2.12.1-6.fc44.noarch.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.x86_64.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.aarch64.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.ppc64le.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.s390x.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.src.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
            touch $output_file_dir/logs/hello-debuginfo-2.12.1-6.fc44.aarch64.rpm.log
        elif [[ "$args" == *"quay.io/test/alreadyexists"* ]]; then
            # Create the same files; they will be "empty", so sha256 matches the mock artifact
            echo "all" > "${CONTENT_EXISTS_MODE_FILE}"
            touch $output_file_dir/hello-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.src.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-docs-2.12.1-6.fc44.noarch.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.aarch64.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.ppc64le.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.s390x.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.src.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
        elif [[ "$args" == *"quay.io/test/digestmismatch"* ]]; then
            # Pretend content exists in Pulp, but make local RPM digests differ from the (mocked) server artifact digest.
            # This drives the "exists but digest differs" path.
            echo "all" > "${CONTENT_EXISTS_MODE_FILE}"
            printf '%s\n' "not-empty" > $output_file_dir/hello-2.12.1-6.fc44.aarch64.rpm
            printf '%s\n' "not-empty" > $output_file_dir/hello-2.12.1-6.fc44.ppc64le.rpm
            printf '%s\n' "not-empty" > $output_file_dir/hello-2.12.1-6.fc44.s390x.rpm
            printf '%s\n' "not-empty" > $output_file_dir/hello-2.12.1-6.fc44.src.rpm
            printf '%s\n' "not-empty" > $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            printf '%s\n' "not-empty" > $output_file_dir/hello-docs-2.12.1-6.fc44.noarch.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.aarch64.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.ppc64le.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.s390x.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.src.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
        elif [[ "$args" == *"quay.io/test/happypath"* ]]; then
            # For happy path, pretend content does not exist so uploads proceed
            echo "none" > "${CONTENT_EXISTS_MODE_FILE}"
            touch $output_file_dir/hello-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.src.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-docs-2.12.1-6.fc44.noarch.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.aarch64.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.ppc64le.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.s390x.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.x86_64.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.aarch64.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.ppc64le.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.s390x.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.src.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
            touch $output_file_dir/logs/hello-debuginfo-2.12.1-6.fc44.aarch64.rpm.log
        elif [[ "$args" == *"quay.io/test/onlyrpms"* ]]; then
            touch $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-debuginfo-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-debugsource-2.12.1-6.fc44.x86_64.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
            touch $output_file_dir/logs/hello-debuginfo-2.12.1-6.fc44.x86_64.rpm.log
            touch $output_file_dir/logs/hello-debugsource-2.12.1-6.fc44.x86_64.rpm.log
        elif [[ "$args" == *"quay.io/test/onlynoarch"* ]]; then
            touch $output_file_dir/hello-2.12.1-6.fc44.noarch.rpm
            # mimic having logs from each rpm build
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.noarch.rpm.log
        elif [[ "$args" == *"quay.io/test/x86andnoarch"* ]]; then
            # x86_64 + noarch only (no other arch binaries); noarch must be pushed to all default arch repos
            echo "none" > "${CONTENT_EXISTS_MODE_FILE}"
            touch $output_file_dir/hello-2.12.1-6.fc44.x86_64.rpm
            touch $output_file_dir/hello-docs-2.12.1-6.fc44.noarch.rpm
            touch $output_file_dir/hello-2.12.1-6.fc44.src.rpm
            mkdir -p $output_file_dir/logs
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.x86_64.rpm.log
            touch $output_file_dir/logs/hello-docs-2.12.1-6.fc44.noarch.rpm.log
            touch $output_file_dir/logs/hello-2.12.1-6.fc44.src.rpm.log
        else
            echo Error: Unexpected call
            exit 1
        fi

    fi
}
