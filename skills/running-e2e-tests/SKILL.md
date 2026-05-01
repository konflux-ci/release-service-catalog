---
name: running-e2e-tests
description: Use when verifying cross-component behavior, debugging CI e2e failures, or testing deployment pipelines. Use when integration tests fail or a PR changes multiple services.
---

# Running E2E / Integration Tests

## E2E Test Locations

- `integration-tests/`

## Kind Cluster Setup

This repo uses [kind](https://kind.sigs.k8s.io/) for local Kubernetes testing.

```bash
# Create a kind cluster (check hack/ or Makefile for project-specific config)
kind create cluster --name test-cluster
```

Tear down after testing:
```bash
kind delete cluster --name test-cluster
```

## Tips

- E2E tests may require a running cluster or external services
- Check CI workflow files for the exact setup steps used in automated runs
- Clean up test resources after running to avoid state leakage

## Output Format

When reporting e2e results, use:

```markdown
## E2E Test Results

**Test suite:** <name>
**Status:** PASS / FAIL
**Failed tests:** <test names>
**Category:** A (test code) / B (app code) / C (infra/flaky)
**Root cause:** <analysis>
**Suggested fix:** <file and change>
```
