# Local Testing Guide

Run Tekton task tests locally for fast feedback before submitting PRs. The local environment mirrors CI exactly, ensuring tests that pass locally will pass in CI.

## Quick Start

```bash
# One-time setup (5-10 minutes)
./scripts/local-test-env.sh setup
source .env.testing

# Run tests  
./scripts/run-local-tests.sh                    # Test changed files
./scripts/run-local-tests.sh --pr-mode          # Test PR changes
./scripts/run-local-tests.sh --parallel 2       # Parallel execution
./scripts/run-local-tests.sh tasks/managed/add-fbc-contribution  # Specific task
```

## Prerequisites

Required tools: **podman**, **kind**, **kubectl**, **yq**, **jq**

Installation:
```bash
# macOS
brew install podman kind kubectl yq jq

# Fedora/RHEL  
sudo dnf install -y podman kubectl yq jq
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# Ubuntu/Debian
sudo apt-get install -y podman jq
# (see setup script for kind, kubectl, yq installation)
```

The setup script will check for missing tools and guide installation.

## Common Usage

```bash
# Test specific tasks
./scripts/run-local-tests.sh tasks/managed/add-fbc-contribution
./scripts/run-local-tests.sh tasks/managed/apply-mapping tasks/internal/update-fbc-catalog

# Test options
./scripts/run-local-tests.sh --dry-run                    # Preview what will be tested
./scripts/run-local-tests.sh --parallel 3                # Run 3 tests concurrently 
./scripts/run-local-tests.sh --remove-compute-resources   # For resource-constrained environments
./scripts/run-local-tests.sh --cleanup                    # Clean up after completion

# Results tracking
cat test-results/summary.txt                              # View test summary
ls test-results/                                          # Browse individual results
```

## Environment Setup

```bash
# Setup creates a Kind cluster with Tekton and local registry
./scripts/local-test-env.sh setup

# Configure shell environment (run after setup and in each new shell)
source .env.testing

# Verify setup
kubectl cluster-info
tkn version
```

**First-time setup takes 5-10 minutes.** Subsequent testing sessions only require `source .env.testing`.

## Environment Management

```bash
# Teardown environment 
./scripts/local-test-env.sh teardown              # Remove cluster (keep env files)
./scripts/local-test-env.sh teardown --all        # Remove everything including env files
./scripts/local-test-env.sh teardown --cluster-only # Remove only cluster

# Fresh restart
./scripts/local-test-env.sh reset                 # Teardown + setup with prompts
./scripts/local-test-env.sh reset --force         # Reset without prompts
```

## Troubleshooting

### Quick Fixes

| Issue | Solution |
|-------|----------|
| "kubectl context not set" | `source .env.testing` |
| "Cannot access cluster" | `kind get clusters` → re-run setup if missing |
| "Registry connection issues" | Check port-forward: `ps aux \| grep 30001` |
| Tests failing to start | `kubectl get pods -n tekton-pipelines` |

### Debugging Test Failures

```bash
# View test logs
tkn pr list                           # List recent runs
tkn pr logs <pipelinerun-name>        # View specific test logs

# Check test results
cat test-results/summary.txt          # Overall results summary
cat test-results/<task-name>.log      # Individual task results

# Manual cleanup if needed
kubectl delete pipelinerun --all
kubectl delete taskrun --all
```

## Advanced Usage

### Workflow Modes

The test runner automatically detects and uses the appropriate workflow:
- **Trusted Artifacts** - For tasks with `ociStorage` parameter (modern)
- **PVC** - For legacy tasks using Persistent Volume Claims

Override with `--trusted-artifacts` or `--pvc` flags if needed.

### Resource Management

```bash
# For resource-constrained environments
./scripts/run-local-tests.sh --remove-compute-resources

# Custom cluster name
export CLUSTER_NAME="my-test-cluster"
./scripts/local-test-setup.sh
```

## Cleanup

```bash
# Clean up test resources only
kubectl delete pipelinerun --all
kubectl delete taskrun --all

# Remove entire cluster
kind delete cluster --name release-service-catalog

# Reset environment
rm -f .env.testing
```

## Best Practices

- **Test locally first** - Faster feedback than CI
- **Use `--pr-mode`** before submitting PRs
- **Keep clusters running** - Reuse between test sessions
- **Check results** - Always review `test-results/summary.txt`
- **Parallel testing** - Use `--parallel N` for independent tests

## More Information

- [CONTRIBUTING.md](../CONTRIBUTING.md) - General contribution guidelines
- [Tekton Documentation](https://tekton.dev/docs/) - Official Tekton documentation