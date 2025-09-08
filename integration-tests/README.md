# Integration Tests

This directory contains end-to-end integration tests for the Release Service Catalog. These tests validate the functionality of release pipelines by simulating complete workflows including environment setup, secret decryption, GitHub interactions, Kubernetes resource management, and release verification.

## Test Suites

The following integration test suites are available:

- **[collectors](collectors/)** - Tests for advisory data collection and processing
- **[fbc-release](fbc-release/)** - Tests for File-Based Catalog (FBC) release pipeline
- **[push-to-addons-registry](push-to-addons-registry/)** - Tests for pushing to addon registries
- **[rh-push-to-external-registry](rh-push-to-external-registry/)** - Tests for pushing to external registries
- **[release-to-github](release-to-github/)** - Tests for GitHub release pipeline
- **[rhtap-service-push](rhtap-service-push/)** - Tests for RHTAP service push pipeline

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

### Examples

```bash
# Run fbc-release test
./run-test.sh fbc-release

# Run test with debugging (skip cleanup)
./run-test.sh fbc-release --skip-cleanup
```

## Debugging

### Debug Options

When debugging test failures, use the `--skip-cleanup` option to preserve resources for examination:

```bash
./run-test.sh <test-suite-name> --skip-cleanup
```

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

## Troubleshooting

### Common Issues

1. **Authentication Errors** - Verify GitHub token has correct permissions
2. **Cluster Access** - Ensure KUBECONFIG is properly configured
3. **Secret Errors** - Check vault password file exists and is correct
4. **Resource Conflicts** - Use cleanup scripts to remove stale resources

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
