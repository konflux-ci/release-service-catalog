#!/usr/bin/env bash
#
# run-suite-unit-tests.sh - Run executable test-*.sh scripts under integration test suites.
#
# Suite test.sh files are sourced by run-test.sh for e2e flows. Scripts named test-*.sh
# (other than patterns that match only dedicated unit tests) are standalone unit tests.
#
# Usage:
#   ./run-suite-unit-tests.sh [suite ...]
#
# With no arguments, runs every integration-tests/<suite>/test-*.sh found.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INTEGRATION_TESTS_DIR="${SCRIPT_DIR}"

require_commands() {
    local missing=()
    for cmd in bash jq base64 yq; do
        command -v "${cmd}" >/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "🔴 missing required commands: ${missing[*]}" >&2
        exit 2
    fi
}

run_unit_tests_in_suite() {
    local suite_dir="${1}"
    local test_script

    if [[ ! -d "${suite_dir}" ]]; then
        echo "🔴 unknown suite: $(basename "${suite_dir}")" >&2
        return 1
    fi

    shopt -s nullglob
    local test_scripts=("${suite_dir}"/test-*.sh)
    shopt -u nullglob

    for test_script in "${test_scripts[@]}"; do
        if [[ ! -x "${test_script}" ]]; then
            echo "🔴 ${test_script} must be executable" >&2
            return 1
        fi
        echo "Running ${test_script}..."
        bash "${test_script}"
    done
}

main() {
    require_commands

    if [[ $# -gt 0 ]]; then
        local suite suite_dir
        for suite in "$@"; do
            suite_dir="${INTEGRATION_TESTS_DIR}/${suite}"
            if [[ ! -f "${suite_dir}/test.sh" ]]; then
                echo "🔴 ${suite} is not an integration test suite (missing test.sh)" >&2
                return 1
            fi
            run_unit_tests_in_suite "${suite_dir}"
        done
        return 0
    fi

    local suite_dir
    for suite_dir in "${INTEGRATION_TESTS_DIR}"/*/; do
        [[ -f "${suite_dir}/test.sh" ]] || continue
        run_unit_tests_in_suite "${suite_dir}"
    done
}

main "$@"
