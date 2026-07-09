---
name: debug-e2e
description: Debug failing e2e tests on a PR.
disable-model-invocation: true
---

## Prerequisites

Required tools: `jq`, `gh`, `kubectl` (or `oc`), `kubectl-ka` (KubeArchive plugin)

Before starting, verify all required tools are installed:

```sh
for cmd in jq gh kubectl; do command -v "${cmd}" &>/dev/null || echo "MISSING:${cmd}"; done
kubectl plugin list 2>/dev/null | grep -q kubectl-ka || echo "MISSING:kubectl-ka"
```

If any tool is missing, stop and tell the user which ones are missing. For `kubectl-ka`, link to: https://konflux.pages.redhat.com/docs/users/faq/kubearchive.html

$ARGUMENTS is a GitHub PR URL (e.g. `https://github.com/konflux-ci/release-service-catalog/pull/2328`).

## Steps

### 1. Fetch failed e2e checks

```sh
scripts/get-failed-e2e-checks.sh $ARGUMENTS
```

This outputs a JSON array. Each element has these fields:
- `name` — the check name
- `pipelinerun` — the PipelineRun name (e.g. `collector-e2e-test-rlx2d`)
- `pipelinerun_url` — direct link to the Konflux UI
- `namespace` — the namespace (e.g. `rhtap-release-2-tenant`)
- `tasks[]` — array of tasks with `task`, `passed`, `duration`, `logs_url`

### 2. For each failed check, fetch the failing TaskRuns

Use the `pipelinerun` and `namespace` fields from step 1. Try `kubectl get` first (live cluster), and if it returns empty results, fall back to `kubectl ka get` (KubeArchive):

```sh
kubectl get taskrun -n <namespace> \
    -l tekton.dev/pipelineRun=<pipelinerun> \
    -o json | jq '[
      .items[]
      | (.status.results // [] | map(select(.name == "TEST_OUTPUT")) | first // null) as $test
      | {
          name: .metadata.name,
          task: .metadata.labels["tekton.dev/pipelineTask"],
          pod: .status.podName,
          test_output: ($test.value | fromjson? // null)
        }
      | select(.test_output.result == "FAILURE")
    ]'
```

If the above returns an empty array or errors, retry with `kubectl ka get` instead of `kubectl get` (the resources may have been archived). Once any `kubectl ka` fallback succeeds, use `kubectl ka` directly for all subsequent cluster calls in this session (TaskRun fetches, log fetches, etc.).

Important: TaskRun conditions will show `Succeeded` even for test failures because the test script traps errors and always exits 0. The actual result is in the `TEST_OUTPUT` result (`result: "FAILURE"`).

### 3. Fetch logs from each failed TaskRun's pod

Use the `pod` and `namespace` from step 2. 

```sh
kubectl logs -n <namespace> <pod> -c step-run-test
```

The `-c step-run-test` flag is required. Tekton pods have multiple containers and the test output is in the `step-run-test` container.

### 4. Summarize

Provide a table with the following structure:

```
| Test Name | Failure Cause | Konflux UI Link |
|-----------|---------------|-----------------|
| <short test name> | <one-line failure cause> | <pipelinerun_url> |
```

- Use the full `https://...` URL in the Konflux UI Link column.
- After the table, provide a root cause analysis summarizing the failure patterns. Include relevant log snippets (key error messages, timeout lines, or stack traces) that show exactly why the pipeline failed. Group tests that share the same root cause together.
