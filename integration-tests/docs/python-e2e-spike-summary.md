# Python E2E Testing Spike Summary

## Overview

This document summarizes findings from implementing a Python-based E2E testing solution for the release-service-catalog, migrating the existing `integration-tests/e2e` bash test as a proof of concept.

## Framework Selection

### Chosen Stack

| Component | Library | Purpose |
|-----------|---------|---------|
| Test Framework | **pytest** | Industry standard, excellent fixture system, rich plugin ecosystem |
| Async Support | **pytest-asyncio** | Native async/await for concurrent K8s operations |
| Kubernetes | **kubernetes (official client)** | Direct API access for status monitoring |
| GitHub API | **PyGithub** | Official GitHub library for repo/PR operations |
| Configuration | **pydantic-settings** | Type-safe config with environment variable loading |
| Retries | **tenacity** | Robust retry logic with exponential backoff |

### Why pytest?

- **Fixtures**: Session-scoped fixtures naturally map to test lifecycle (setup → test → cleanup)
- **Async support**: `pytest-asyncio` enables concurrent waits (e.g., multiple Releases)
- **CI integration**: Native JUnit XML output, easy integration with Tekton tasks
- **Extensibility**: Plugin ecosystem for timeouts, coverage, parallel execution

### Alternatives Considered

| Framework | Verdict |
|-----------|---------|
| `behave` (BDD) | Overkill for our needs; Gherkin adds overhead without clear benefit |
| `pytest-operator` | Designed for Juju/Charmed operators, not Tekton |
| `robot framework` | Keyword-driven approach less suitable for infrastructure tests |

## Architecture

```
integration-tests/
├── pylib/                    # Shared Python library
│   ├── config.py             # Base configuration class
│   ├── conftest_base.py      # Generic pytest fixtures
│   ├── github.py             # GitHub API client
│   ├── kubernetes.py         # Kubernetes client + status monitoring
│   ├── resources.py          # Kustomize + resource management
│   ├── runner.py             # Test runner utilities
│   ├── utils.py              # Logging, retries, shell commands
│   ├── vault.py              # Ansible Vault decryption
│   └── requirements.txt      # Python dependencies
│
├── e2e/                      # Migrated test suite
│   ├── conftest.py           # Imports generic fixtures, defines test_config
│   ├── lib/config.py         # E2E-specific configuration
│   ├── run_test.py           # Entry point (replaces test.sh)
│   ├── test_e2e.py           # Actual test assertions
│   ├── test.env              # Resource names (unchanged from bash)
│   └── resources/            # Kustomize overlays (unchanged)
│
└── <other-suites>/           # Future migrations (same pattern)
```

## Key Capabilities

### 1. Kubernetes/Tekton Interaction

```python
# Direct API access for status monitoring
k8s_client = KubernetesClient()
status = await k8s_client.wait_for_release_completion(name, namespace, timeout=1800)

# kubectl for YAML operations (simpler than native client for CRDs)
await k8s_client.kubectl_yaml("create", yaml_content, namespace)
```

**Approach**: Hybrid - use `kubectl` for apply/create/delete (handles CRDs without schema), official client for status polling.

### 2. Resource Management

- **Kustomize**: Existing overlays work unchanged
- **Variable substitution**: Python `re.sub` replaces `envsubst`
- **Cleanup**: Fixture finalizers ensure cleanup even on test failure

### 3. Test Environment

- **Configuration**: Pydantic models with environment variable loading
- **Secrets**: Ansible Vault decryption (unchanged from bash)
- **Isolation**: UUID-based resource naming prevents collisions

### 4. GitHub Integration

```python
github_client = GitHubClient(token)
await copy_branch_to_repo(source_repo, target_repo, branch)
pr = await github_client.create_pull_request(repo, title, head, base)
result = await github_client.merge_pull_request(repo, pr_number)
```

## Comparison: Bash vs Python

| Aspect | Bash | Python |
|--------|------|--------|
| **Readability** | Scripts grow unwieldy | Clear structure, type hints |
| **Error handling** | `set -e` + manual checks | Exceptions, structured errors |
| **Async operations** | Background jobs, `wait` | Native async/await |
| **Test reporting** | Manual output parsing | JUnit XML, pytest plugins |
| **Debugging** | echo statements | IDE debugging, stack traces |
| **Reusability** | Source scripts | Import modules |
| **Dependencies** | System tools | pip + venv |

## Trade-offs

### Advantages of Python

1. **Maintainability**: Type hints, IDE support, clear structure
2. **Concurrent waits**: `asyncio.gather()` for multiple Releases
3. **Better error messages**: Stack traces with context
4. **Fixture system**: Declarative setup/teardown with dependency injection
5. **Extensibility**: Easy to add new assertions, reporters

### Disadvantages

1. **venv management**: Additional setup step vs bash
2. **Debugging async**: Async stack traces can be confusing

## Recommendations

### Phase 1: Stabilize e2e Migration
- [x] Complete e2e migration (done in this spike)
- [ ] Run in CI alongside bash version to validate parity
- [ ] Document any behavioral differences

### Phase 2: Migrate Additional Suites

### Phase 3: Deprecate Bash
- Remove bash versions once Python equivalents are validated
- Keep `lib/test-functions.sh` for any remaining bash utilities

### Not Recommended
- Using native Python K8s client for CRD YAML operations (kubectl is simpler)
- Adding BDD/Gherkin layer (unnecessary complexity)

## Files Created/Modified

### New Files (pylib/)
- `config.py`, `conftest_base.py`, `github.py`, `kubernetes.py`
- `resources.py`, `runner.py`, `utils.py`, `vault.py`
- `requirements.txt`, `pytest.ini`, `__init__.py`

### New Files (e2e/)
- `conftest.py`, `lib/config.py`, `run_test.py`, `test_e2e.py`
- `lib/__init__.py`, `__init__.py`

### Unchanged
- `test.env`, `resources/` directory, `vault/` directory

### Can Be Removed (after validation)
- `test.sh` (replaced by `run_test.py`)
