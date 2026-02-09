# rh-advisories-large-snapshot test

## Overview

This test validates the rh-advisories pipeline with a large snapshot (~200 components) to ensure it can handle production-scale workloads. The test uses pre-built container images to skip the build phase and focus on advisory creation and processing at scale.

**Expected Duration:** 4-8 hours due to processing ~200 components at scale.

## Setup

### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**, **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you want to run this
  test suite.)
* Access to the target cluster and tenant and managed namespaces
  * **Cluster:** stg-rh01 (staging cluster)
  * **PaC Runs:** Execute in `rhtap-release-2-tenant` (triggered by `/test-large-snapshot` comment)
  * **Local Runs:** Default to `dev-release-team-tenant` (can be overridden via `tenant_namespace` variable)
  * **Managed Namespace:** Both use `managed-release-team-tenant` for release pipelines

### Required Environment Variables
- GITHUB_TOKEN
  - The GitHub personal access token needed for repo operations
  - The repo in question can be located in [test.env](test.env)
- VAULT_PASSWORD_FILE
  - This is the path to a file that contains the ansible vault
    password needed to decrypt the secrets needed for testing.
- RELEASE_CATALOG_GIT_URL
  - The release service catalog URL to use in the RPA
  - This is provided when testing PRs
- RELEASE_CATALOG_GIT_REVISION
  - The release service catalog revision to use in the RPA
  - This is provided when testing PRs

### Optional Environment Variables
- KUBECONFIG
  - The KUBECONFIG file to used to login to the target cluster
  - This is provided when testing PRs

### Test Properties
#### [test.env](test.env)
- This file contains resource names and configuration values needed for testing.
- This test creates a large snapshot with pre-built components to test advisory creation at scale.
- The component count is configurable via `LARGE_SNAPSHOT_COMPONENT_COUNT` (default: 200).
- Since this test requires internal services, the tenant and managed namespaces
  should remain as-is.

#### [test.sh](test.sh)
- This file contains specific variables and functions needed for the test.
- Overrides standard functions to skip builds and use pre-built images.

### Test Functions
#### [lib/test-functions.sh](../lib/test-functions.sh)
- This file contains re-usable functions for tests

### Secrets
- Secrets needed for testing are stored in ansible vault files.
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)
- The secrets required are contained in the files above.

## Running the test

### Prerequisites

**Important:** Before triggering this test, ensure the PR build is complete:

- The `release-service-catalog-on-pull-request` build pipeline must finish successfully
- The container image must be available in the SNAPSHOT
- The test extracts the container image from SNAPSHOT to use in the large snapshot test
- Typical PR build time: 5-8 minutes

**Note:** If triggered before the build completes, the test will use whatever image is in SNAPSHOT (which may be stale or missing).

### Via Pull Request (Recommended)

This test can be triggered via PR comment on any PR in the `release-service-catalog` repository:

```
/test-large-snapshot
```

The PaC configuration ([.tekton/rh-advisories-large-snapshot.yaml](../../.tekton/rh-advisories-large-snapshot.yaml)) 
will trigger the Tekton pipeline automatically.

### Local Testing

For local development and debugging:

```shell
../run-test.sh rh-advisories-large-snapshot
```

To override the tenant namespace for local testing:

```shell
export tenant_namespace=rhtap-release-2-tenant
../run-test.sh rh-advisories-large-snapshot
```

**Note:** The namespace must have the required secrets configured (vault-password-secret, github-token-secret, kubeconfig-secret).

## Debugging

There is a `--skip-cleanup` option to the script in the event that you want to examine the resources
after a test has ended.

## Maintenance

- Should you require to add or update a secret, follow these steps:
```shell
ansible-vault decrypt vault/tenant-secrets.yaml --output "/tmp/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
vi /tmp/tenant-secrets.yaml
```

```shell
ansible-vault encrypt /tmp/tenant-secrets.yaml --output "vault/tenant-secrets.yaml" --vault-password-file <vault password file>
```

```shell
rm /tmp/tenant-secrets.yaml
```
