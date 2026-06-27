# push-artifacts-to-cdn Test

This test validates the `push-artifacts-to-cdn` pipeline with three components:

- **Component 1** (`push-artifacts-cdn-<uuid>`): releases 3 binary files (Windows, Linux, macOS)
  to both the **Customer Portal (Pulp/CDN)** and the **Content Gateway (CGW)**.
  It has both a `staged` section (for Pulp) and a `contentGateway` section in the RPA mapping.

- **Component 2** (`push-artifacts-cdn-comp2-<uuid>`): releases 3 binary files (Windows, Linux, macOS)
  to the **Content Gateway (CGW) only** (no Pulp push).
  It has a `contentGateway` section but no `staged` section in the RPA mapping.

- **Component 3** (`push-artifacts-cdn-comp3-<uuid>`): releases 1 disk-image file (QCOW2)
  to both the **Customer Portal (Pulp/CDN)** and the **Content Gateway (CGW)**, using
  `contentGateway.contentType: disk-image`. It has both a `staged` section (for Pulp) and a
  `contentGateway` section in the RPA mapping.

Auto-release is disabled. The test waits for all three component builds to complete, then manually
creates a Release against the multi-component Snapshot. After the release pipeline succeeds:

1. Asserts the `push-artifacts-to-cdn` TaskRun succeeded.
2. Prints the current file list from the CGW staging API for this product/version.
3. Prints the current file list from the Pulp staging repository (informational).

## Test-Specific Dependencies

In addition to the [common dependencies](../README.md#dependencies), this test requires:

### GitHub Repository Branches

Three base branches must exist in `https://github.com/hacbs-release-tests/e2e-base`:

#### `push-artifacts-to-cdn-comp1-base`
Contains a `Dockerfile` and 3 `.tar.gz` archives for Component 1 (Pulp + CGW).
Each archive wraps one **jq 1.7.1** binary from https://github.com/jqlang/jq/releases/tag/jq-1.7.1:
```
/releases/e2e-cdn-comp1-windows-amd64.tar.gz  ← contains jq-windows-amd64.exe (PE32+)
/releases/e2e-cdn-comp1-linux-amd64.tar.gz    ← contains jq-linux-amd64 (ELF x86_64)
/releases/e2e-cdn-comp1-darwin-amd64.tar.gz   ← contains jq-macos-amd64 (Mach-O x86_64)
```

#### `push-artifacts-to-cdn-comp2-base`
Contains a `Dockerfile` and 3 `.tar.gz` archives for Component 2 (CGW only).
Each archive wraps one **jq 1.6** binary from https://github.com/jqlang/jq/releases/tag/jq-1.6:
```
/releases/e2e-cdn-comp2-windows-amd64.tar.gz  ← contains jq-win64.exe (PE32+)
/releases/e2e-cdn-comp2-linux-amd64.tar.gz    ← contains jq-linux64 (ELF x86_64)
/releases/e2e-cdn-comp2-darwin-amd64.tar.gz   ← contains jq-osx-amd64 (Mach-O x86_64)
```

#### `push-artifacts-to-cdn-comp3-base`
Contains a `Dockerfile` and one small QCOW2 disk image for Component 3 (Pulp + CGW):
```
/releases/e2e-cdn-comp3-rhel10-x86_64.qcow2  ← small QCOW2 image, os: linux only
```
Disk images are passed straight through the pipeline (no signing, no compression).

> **Important**: The Windows and Mac binaries inside the comp1/comp2 archives must be real
> PE/Mach-O executables because the pipeline extracts and submits them to production signing
> hosts. The pipeline re-packages the output: Windows → `.zip`, Linux/macOS → `.tar.gz`.

### Required Secrets in `managed-release-team-tenant` (stg-rh01)

The following secrets must exist in the managed namespace before running the test.
Most are shared permanent secrets used by production pipelines.

| Secret Name | Purpose |
|-------------|---------|
| `exodus-prod-secret` | Exodus Gateway credentials (used for stage env with `pre` environment) |
| `rhsm-pulp-stage-secret` | Pulp staging credentials — keys: `pulp_url`, `konflux-release-rhsm-pulp.crt`, `konflux-release-rhsm-pulp.key` (mutual TLS) |
| `udcache-stage-secret` | UDCache staging credentials |
| `cgw-service-account-stage-secret` | CGW staging credentials (developers.qa.redhat.com) |
| `quay-credentials` | Write access to `quay.io/konflux-artifacts/nonprod` (ORAS staging) |
| `windows-credentials` | Windows signing host credentials |
| `windows-ssh-key` | SSH private key for Windows signing host |
| `mac-host-credentials` | Mac signing host connection info |
| `mac-signing-credentials` | Mac signing utility credentials |
| `mac-ssh-key` | SSH private key for Mac signing host |
| `checksum-credentials` | Kerberos keytab + host + fingerprint for GPG checksum signing |
| `redhat-workloads-token` | Pull token for the RSU container image |
| `quay-token-konflux-release-trusted-artifacts-secret` | Trusted Artifacts OCI push/pull |

### Required ConfigMap in `managed-release-team-tenant` (stg-rh01)

| ConfigMap Name | Purpose |
|---------------|---------|
| `hacbs-signing-pipeline-config-staging-e2e` | Signing pipeline config; must contain `data.SIG_KEY_NAME` or `data.SIG_KEY_NAMES` |

### CGW Product (stage)

The test uses the Konflux e2e test product on the **staging CGW** (`https://developers.qa.redhat.com`):

- **Product Code**: `KonfluxReleaseE2E`
- **Product Name**: `Konflux Release E2E test product`
- **Product Version**: `1.0`

### Pulp Staging Repository

The test uses Pulp repository `konflux-release-e2e-1_DOT_0-for-rhel-10-x86_64-files` on
`rhsm-pulp.corp.stage.redhat.com`.
(shadow eng product ID `10681`, never visible to customers). No action required.

## Vault Files

The vault files must be encrypted with ansible-vault before the test can run:

1. Edit `vault/tenant-secrets.yaml.template` — fill in real GitHub PAC tokens.
2. Encrypt and place at `vault/tenant-secrets.yaml`:
   ```bash
   ansible-vault encrypt vault/tenant-secrets.yaml.template \
     --output vault/tenant-secrets.yaml \
     --vault-password-file <vault-password-file>
   ```
3. For managed secrets, the `vault/managed-secrets.yaml.template` shows an empty list
   (all required secrets are shared permanent secrets). Encrypt it:
   ```bash
   ansible-vault encrypt vault/managed-secrets.yaml.template \
     --output vault/managed-secrets.yaml \
     --vault-password-file <vault-password-file>
   ```

## Running the Test

```bash
../run-test.sh push-artifacts-to-cdn
```

With debug (skip cleanup on failure):
```bash
../run-test.sh push-artifacts-to-cdn --skip-cleanup
```

## Test Workflow

1. **GitHub Setup** — Creates component GitHub repos from the three base branches in e2e-base.
2. **Konflux Onboarding** — Creates Application, 3 Components, ReleasePlan, and ReleasePlanAdmission.
3. **Component Builds** — Waits for all three components' Konflux build PipelineRuns to complete.
   Each component builds a container image containing the test binary/disk-image files.
4. **Multi-Component Snapshot** — Waits for a Snapshot containing all three components.
5. **Manual Release** — Creates a Release CR against the multi-component Snapshot.
6. **Pipeline Execution** — Monitors the `push-artifacts-to-cdn` managed pipeline:
   - `collect-data`, `reduce-snapshot`, `apply-mapping` run first.
   - `push-artifacts-to-cdn` (managed task) creates an InternalRequest.
   - InternalRequest triggers the internal pipeline on the internal services cluster.
   - Internal pipeline: extracts binaries/disk-images → pushes unsigned to Quay (ORAS) →
     signs binaries via Mac/Windows signing hosts (disk images pass through unsigned) →
     compresses binaries (disk images pass through uncompressed) → generates checksums →
     pushes to Pulp (comp1 and comp3) → pushes to CGW (all three comps) →
     pushes checksum file to CGW.
7. **Verification**:
   - Asserts the `push-artifacts-to-cdn` TaskRun succeeded.
   - Prints the current file list from the CGW staging API (informational).
   - Prints the current file list from the Pulp staging API (informational).

## Verification Checks

`verify_release_contents()` asserts the following hard pass/fail condition:

- **push-artifacts-to-cdn TaskRun** — succeeded (status=True).

After that assertion, the test prints the current state of both downstream systems as
diagnostic output but does **not** fail based on their content.

### Why CGW and Pulp content is not asserted

CGW is idempotent: files are skipped if one already exists with the same label and
URL, so the product version does not accumulate duplicates across runs. Similarly
with pulp: `pulp_push_wrapper` prunes older timestamped variants of each file before
pushing, so only the most recent run's files remain in the repository.

The fundamental problem is attribution: all e2e runs share the same CGW product
version (`KonfluxReleaseE2E/1.0`) and Pulp repository. There is no trivial way to
determine which files in that version or repository were created by the current run
versus a previous or concurrent one. Asserting against CGW or Pulp content would 
require a dedicated product version per run, which would mean dynamically creating
and deleting CGW product versions for every integration test — an unreasonable 
burden on the staging CGW service.

The primary signal that the pipeline did the right thing is therefore the TaskRun
success status. The CGW and Pulp state printouts serve as a manual reference for
debugging when the pipeline fails.
