#mocks.sh
#!/usr/bin/env bash
set -eux
function curl() {
    if [[ "$*" == *"https://raw.githubusercontent.com/konflux-ci/release-service-catalog/refs/heads/production/schema/non-existent-schema.json"* ]]; then
        command curl -s --fail-with-body "$@" -o /tmp/schema
    else
        command curl -s --fail-with-body  https://raw.githubusercontent.com/konflux-ci/release-service-catalog/refs/heads/development/schema/dataKeys.json -o /tmp/schema
    fi
}
