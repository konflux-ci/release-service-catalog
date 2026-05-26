# Integration Tests

This directory contains end-to-end integration tests for the Release Service Catalog. These tests validate the functionality of release pipelines by simulating complete workflows including environment setup, secret decryption, GitHub interactions, Kubernetes resource management, and release verification.

## Test Suites

The following integration test suites are available:

- **[collectors](collectors/)** - Tests for advisory data collection and processing
- **[fbc-release](fbc-release/)** - Tests for File-Based Catalog (FBC) release pipeline
- **[push-to-addons-registry](push-to-addons-registry/)** - Tests for pushing to addon registries
- **[rh-push-helm-chart-to-registry-redhat-io](rh-push-helm-chart-to-registry-redhat-io/)** - Tests for Helm OCI chart release pipeline
- **[rh-push-to-external-registry](rh-push-to-external-registry/)** - Tests for pushing to external registries
- **[release-to-github](release-to-github/)** - Tests for GitHub release pipeline
- **[rhtap-service-push](rhtap-service-push/)** - Tests for RHTAP service push pipeline
- **[rh-advisories-large-snapshot](rh-advisories-large-snapshot/)** - **Manual test** for rh-advisories pipeline with large snapshots (~200 components)
  - **Trigger**: Comment `/test-large-snapshot` on any PR
  - **Duration**: 4-8 hours
  - **⚠️ Hard Requirements**:
    - **Cluster**: `stg-rh01` staging cluster only
    - **Namespace**: `rhtap-release-2-tenant` (PaC runs) or `dev-release-team-tenant` (local runs)
    - **Required Secrets** (must exist in namespace): `vault-password-secret`, `github-token-secret`, `kubeconfig-secret`
    - Cannot run in arbitrary clusters/namespaces without infrastructure setup

## Common Setup

### Dependencies

All integration tests require the following dependencies:

* **GitHub Repository**: https://github.com/hacbs-release-tests/e2e-base
* **GitHub Personal Access Token** (classic) for the above repository with the following scopes:
  - `admin:repo_hook`
  - `delete_repo`
  - `repo`
* **Vault Password**: The password to decrypt the vault files (contact a member of the Release team)
* **Cluster Access**: Access to the target cluster and tenant/managed namespaces
  - Tests use `stg-rh01` cluster
  - Tenant namespace: `dev-release-team-tenant`
  - Managed namespace: `managed-release-team-tenant`

### Required Environment Variables

All tests require these environment variables:

- **`GITHUB_TOKEN`** - The GitHub personal access token for repository operations
- **`VAULT_PASSWORD_FILE`** - Path to a file containing the ansible vault password needed to decrypt secrets
- **`RELEASE_CATALOG_GIT_URL`** - The release service catalog URL to use in the ReleasePlanAdmission (provided when testing PRs)
- **`RELEASE_CATALOG_GIT_REVISION`** - The release service catalog revision to use in the ReleasePlanAdmission (provided when testing PRs)

### Optional Environment Variables

- **`KUBECONFIG`** - The KUBECONFIG file used to login to the target cluster (provided when testing PRs)

## Test Structure

Each test suite follows a consistent structure:

### Configuration Files

- **`test.env`** - Contains resource names and configuration values specific to the test
- **`test.sh`** - Contains test-specific variables and functions (may vary by test)

### Shared Libraries

- **`lib/test-functions.sh`** - Contains reusable functions shared across all tests

### Secrets Management

Tests use ansible vault files to store encrypted secrets:
- **`vault/managed-secrets.yaml`** - Secrets for the managed namespace
- **`vault/tenant-secrets.yaml`** - Secrets for the tenant namespace

For the tests that require internal services, the tenant and managed namespaces should remain as configured

## Running Tests

### Basic Usage

To run a specific test suite:

```bash
./run-test.sh <test-suite-name>
```

Example:
```bash
./run-test.sh fbc-release
```

### Command Line Options

- **`--skip-cleanup`** or **`-sc`** - Skip cleanup operations after test completion (useful for debugging)
- **`--no-cve`** or **`-nocve`** - Skip CVE simulation in commit messages and release verification
- **`--interactive`** or **`-i`** - Enable interactive mode for iterative debugging (see [Interactive Mode](#interactive-mode))

### Examples

```bash
# Run fbc-release test
./run-test.sh fbc-release

# Run test with debugging (skip cleanup)
./run-test.sh fbc-release --skip-cleanup

# Run test in interactive mode
./run-test.sh push-rpms-to-pulp --interactive
```

## Debugging

### Debug Options

When debugging test failures, use the `--skip-cleanup` option to preserve resources for examination:

```bash
./run-test.sh <test-suite-name> --skip-cleanup
```

### Interactive Mode

Interactive mode (`-i` or `--interactive`) provides an iterative development experience for debugging release pipeline failures. When a release fails, instead of immediately exiting, the test pauses and presents an interactive menu:

```
🛑 Interactive Mode - Test paused
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [r] Retry    - Create new Release with same snapshot
  [i] Info     - Show release context again
  [s] Shell    - Drop into bash shell (exit to return)
  [c] Cleanup  - Run cleanup and exit
  [q] Quit     - Exit without cleanup (keep resources)
```

**Key Features:**

- **Retry (`r`)**: Creates a new Release CR using the same snapshot. This is useful when you've fixed the underlying pipeline code and want to re-test without rebuilding RPMs or recreating the entire test environment.
- **Info (`i`)**: Displays release context including the Release name, Snapshot, ReleasePlan, managed PipelineRun URL (clickable link to OpenShift console), and namespace information.
- **Shell (`s`)**: Drops into an interactive bash shell with useful environment variables pre-set (`RELEASE_NAME`, `RELEASE_NAMESPACE`, `tenant_namespace`, `managed_namespace`). Type `exit` to return to the menu.
- **Cleanup (`c`)**: Runs the normal cleanup process and exits.
- **Quit (`q`)**: Exits immediately without cleanup, preserving all resources for later debugging.

**Example Usage:**

```bash
# Run test in interactive mode for pipeline development
./run-test.sh push-rpms-to-pulp -i

# Combine with skip-cleanup for maximum flexibility
./run-test.sh fbc-release --interactive --skip-cleanup
```

Interactive mode is particularly useful when:
- Developing or debugging release pipeline tasks
- Iterating on fixes without full test re-runs
- Investigating failures that require manual inspection

### Manual Cleanup

When debugging is complete, you can clean up resources using these scripts:

- **`utils/cleanup-resources.sh`** - Cleans up Kubernetes resources
- **`scripts/delete-branches.sh`** - Cleans up GitHub branches

## Secret Management

### Viewing Secrets

To view encrypted secrets:

```bash
ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
```

### Updating Secrets

To update encrypted secrets:

1. Decrypt the vault file:
   ```bash
   ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
   ```

2. Edit the decrypted file:
   ```bash
   vi /tmp/tenant-secrets.yaml
   ```

3. Re-encrypt the file:
   ```bash
   ansible-vault encrypt /tmp/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" --vault-password-file <vault password file>
   ```

4. Remove the temporary file:
   ```bash
   rm /tmp/tenant-secrets.yaml
   ```

## Test Execution Flow

The integration tests follow this general workflow:

1. **Environment Setup** - Load test-specific configuration and validate required variables
2. **Secret Decryption** - Decrypt and apply required secrets to the cluster
3. **GitHub Operations** - Create branches, make commits, and manage pull requests
4. **Kubernetes Resources** - Create and manage namespaces, applications, components, and releases
5. **Pipeline Execution** - Monitor Konflux Components and Tekton PipelineRuns
6. **Verification** - Validate Release custom resources and pipeline outcomes
7. **Cleanup** - Remove created resources (unless `--skip-cleanup` is specified)

## CI/CD Integration

These integration tests are automatically executed in CI/CD pipelines:

- **Pull Request Triggers** - Tests run when changes are made to relevant pipeline files or the `integration-tests/` directory
- **E2E Pipeline** - Uses `integration-tests/pipelines/e2e-tests-staging-pipeline.yaml`
- **Konflux E2E Pipeline** - Uses `integration-tests/pipelines/konflux-e2e-tests-pipeline.yaml`
- **Periodic E2E Pipeline** - Uses `integration-tests/pipelines/e2e-tests-periodic-pipeline.yaml`
  - Runs all integration suites in one Tekton step
  - **Memory**: 6Gi on the `run-test` step (raised from 2Gi to avoid OOM during parallel setup)
  - **Concurrency**: at most **9** suites at a time by default (`MAX_PARALLEL` pipeline param, overridable per PipelineRun)
  - Component init retries when `kubectl get` is temporarily unavailable under load (`lib/test-functions.sh`)

Local `./run-test.sh` runs one suite at a time; only the periodic pipeline runs many suites in parallel.

## Troubleshooting

### Common Issues

1. **Authentication Errors** - Verify GitHub token has correct permissions
2. **Cluster Access** - Ensure KUBECONFIG is properly configured
3. **Secret Errors** - Check vault password file exists and is correct
4. **Resource Conflicts** - Use cleanup scripts to remove stale resources
5. **OOM or `kubectl create` exit 137 in periodic e2e** - Usually too many suites starting at once or insufficient step memory. The periodic pipeline caps parallelism and sets 6Gi; if failures persist, check Tekton step logs for `Killed` during tenant resource setup.
6. **PaC token unrecognizable error** - The following error:
   ```bash
   Initialization check attempt 6/60...
   ⚠️ Warning: Could not get component PR from annotations: {"pac":{"state":"error","error-id":74,"error-message":"74: Access token is unrecognizable by GitHub"},"message":"done"}
   ```
   This is due to using a new GITHUB_TOKEN env variable but the old one being present in your tenant secrets file. Simply `rm resources/tenant/secrets/tenant-secrets.yaml`
   in whatever test you are running so that a new secrets file will be generated for you with the proper secret

### Getting Help

For issues with integration tests:

1. Check the test-specific README files for additional details
2. Review the test logs for specific error messages
3. Use the `--skip-cleanup` option to examine resources after failure
4. Contact the Release team for vault password or cluster access issues

## Contributing

When adding new integration tests:

1. Follow the established directory structure
2. Create test-specific `test.env` and `test.sh` files
3. Use the common libraries in `lib/test-functions.sh`
4. Store secrets in ansible vault files
5. Update this README with test-specific information
6. Add test-specific documentation to the individual test README
