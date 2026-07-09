#!/usr/bin/env bash

set -euo pipefail

PR_URL="${1:-}"

if [[ -z "${PR_URL}" ]]; then
    echo "Usage: $0 <PR_URL>" >&2
    echo "Example: $0 https://github.com/konflux-ci/release-service-catalog/pull/2328" >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required" >&2
    exit 1
fi

OWNER_REPO=$(echo "${PR_URL}" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
PR_NUM=$(echo "${PR_URL}" | sed -E 's|.*/pull/([0-9]+).*|\1|')

if [[ -z "${OWNER_REPO}" || -z "${PR_NUM}" ]]; then
    echo "Error: could not parse PR URL: ${PR_URL}" >&2
    exit 1
fi

SHA=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUM}" --jq '.head.sha')

FAILED_IDS=$(gh api "repos/${OWNER_REPO}/commits/${SHA}/check-runs" \
    --paginate \
    --jq '.check_runs[] | select(.name | contains("e2e-test")) | select(.conclusion == "failure") | .id')

if [[ -z "${FAILED_IDS}" ]]; then
    echo "[]"
    exit 0
fi

parse_check_output() {
    local RAW_JSON="${1}"
    echo "${RAW_JSON}" | jq '
        .output_text as $text |

        # Extract pipelinerun URL from: <a href="...pipelinerun/NAME">NAME</a>
        ($text | capture("href=\"(?<url>[^\"]*pipelinerun/[^\"]+)\">(?<name>[^<]+)</a>")
            // {url: null, name: null}) as $plr |

        # Extract namespace from URL path: /ns/NAMESPACE/pipelinerun/
        ($plr.url | if . then capture("/ns/(?<ns>[^/]+)/") // {ns: null} else {ns: null} end) as $ns |

        # Parse the markdown task table rows into objects
        [
            $text
            | split("\n")[]
            | select(startswith("| <a "))
            | capture("href=\"(?<logs_url>[^\"]+)\">(?<task>[^<]+)</a>\\s*\\|\\s*(?<duration>[^|]+)\\|[^|]*\\|\\s*(?<status>[^|]+)")
            | .duration |= ltrimstr(" ") | .duration |= rtrimstr(" ")
            | .status |= ltrimstr(" ") | .status |= rtrimstr(" ")
            | .passed = (.status | contains("heavy_check_mark"))
        ] as $tasks |

        {
            id,
            name,
            conclusion,
            started_at,
            completed_at,
            html_url,
            pipelinerun: $plr.name,
            pipelinerun_url: $plr.url,
            namespace: $ns.ns,
            tasks: $tasks
        }
    '
}

RESULTS="["
FIRST=true
while IFS= read -r CHECK_ID; do
    if [[ "${FIRST}" == "true" ]]; then
        FIRST=false
    else
        RESULTS+=","
    fi
    RAW=$(gh api "repos/${OWNER_REPO}/check-runs/${CHECK_ID}" \
        --jq '{
            id,
            name,
            conclusion,
            started_at,
            completed_at,
            html_url,
            output_text: .output.text
        }')
    RESULTS+=$(parse_check_output "${RAW}")
done <<< "${FAILED_IDS}"
RESULTS+="]"

echo "${RESULTS}" | jq .
