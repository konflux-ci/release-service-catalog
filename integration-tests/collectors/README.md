# Collectors Test

This test validates the advisory data collection and processing pipeline.

## Test-Specific Dependencies

In addition to the [common dependencies](../README.md#dependencies), this test requires:

* **JIRA Issue**: At least one JIRA issue that can be found via this query:
  * `'project = "Konflux Release"  AND summary ~ "test issue for collector e2e testing"'`

## Test-Specific Secrets

This test uses specialized vault files with different naming:

- **`vault/collector-managed-secrets.yaml`** - Secrets for the managed namespace
- **`vault/collector-tenant-secrets.yaml`** - Secrets for the tenant namespace

## Test-Specific Command Line Options

The collectors test supports an additional command line option:

- **`--no-cve`** or **`-nocve`** - Skip CVE simulation and validation

## Test Modes

The collectors test supports two execution modes:

### Default Mode (with CVE)
Includes CVE simulation and processing:
```bash
../run-test.sh collectors
```

### No-CVE Mode
Excludes CVE simulation:
```bash
../run-test.sh collectors --no-cve
```

## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values
- **`test.sh`** - Contains collectors-specific variables and functions

Note: The collectors test does not follow the standard `test.sh` structure used by other tests.

## Secret Management

### Vault File Maintenance

To update collectors-specific secrets:

1. Decrypt the vault file:
   ```bash
   ansible-vault decrypt vault/collector-tenant-secrets.yaml --output "/tmp/collector-tenant-secrets.yaml" --vault-password-file <vault password file>
   ```

2. Edit the decrypted file:
   ```bash
   vi /tmp/collector-tenant-secrets.yaml
   ```

3. Re-encrypt the file:
   ```bash
   ansible-vault encrypt /tmp/collector-tenant-secrets.yaml --output "vault/collector-tenant-secrets.yaml" --vault-password-file <vault password file>
   ```

4. Remove the temporary file:
   ```bash
   rm /tmp/collector-tenant-secrets.yaml
   ```

Repeat the same process for `vault/collector-managed-secrets.yaml` as needed.

## Test Workflow

The collectors test follows this specific workflow:

1. **JIRA Integration Setup** - Validates required JIRA issues exist
2. **Advisory Data Collection** - Simulates advisory data gathering
3. **CVE Processing** - Processes CVE data (if not using `--no-cve`)
4. **Release Pipeline Execution** - Executes the advisory collection pipeline
5. **Verification** - Validates collected advisory data and release outcomes
