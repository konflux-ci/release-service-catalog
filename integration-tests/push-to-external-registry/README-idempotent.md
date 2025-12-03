# push-to-external-registry-idempotent test

## Overview
This test suite validates idempotent release behavior by using **two releases with the same snapshot** and verifying that the second release correctly filters already-released components.

## What This Tests
- **First Release**: Automatic release created by Konflux (pushes all components to external registry)
- **Second Release**: Manual release with the same snapshot (should filter already-released components)
- **Idempotency**: Verifies that the pipeline detects already-pushed images and skips redundant pushes
- **Performance**: Measures and compares execution time between initial and idempotent releases
- **Tag Determinism**: Uses static tags (no timestamp) to ensure both releases target identical image tags

## Files Used
This idempotent test reuses most resources from the main `push-to-external-registry` test, with the following overrides:

- **test-idempotent.sh**: Overrides `wait_for_releases()` to wait for the automatic first release, then creates a second release with the same snapshot
- **test-idempotent.env**: Overrides `originating_tool` and `application_name` for idempotent test isolation
- **resources/managed/rpa-idempotent.yaml**: Simplified RPA with deterministic, static tags:
  - Default tags: `latest` only (no `{{ timestamp }}`)
  - Component tags: `{{ git_sha }}`, `{{ git_short_sha }}`, `v1.0.0` (no incrementer, no dynamic tags)
- **resources/managed/kustomization-idempotent.yaml**: References the idempotent RPA variant

All other resources (secrets, service accounts, policies, components, etc.) are shared with the main test.

## Setup
### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**, **delete_repo**, **repo** scopes
* The password to the vault files (Contact a member of the Release team)
* Access to the target cluster and tenant and managed namespaces
  * This test uses stg-rh01 and the dev-release-team-tenant and managed-release-team-tenant namespaces

### Required Environment Variables
- GITHUB_TOKEN
  - The GitHub personal access token needed for repo operations
  - The repo in question can be located in [test-idempotent.env](test-idempotent.env)
- VAULT_PASSWORD_FILE
  - This is the path to a file that contains the ansible vault password needed to decrypt the secrets needed for testing
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
#### [test-idempotent.env](test-idempotent.env)
- This file sources the base [test.env](test.env) and overrides values specific to idempotent testing

### Test Functions
#### [test-idempotent.sh](test-idempotent.sh)
- This file sources the base [test.sh](test.sh) and overrides `wait_for_releases()` to test idempotent behavior

#### [../lib/test-functions.sh](../lib/test-functions.sh)
- This file contains re-usable functions for tests

### Secrets
- Secrets needed for testing are stored in ansible vault files (shared with main test)
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)
- Most secrets required are contained in the files above

## Running the test

The idempotent test is **automatically detected and runs** before the regular test:

```shell
../run-test.sh push-to-external-registry
```

The framework detects `test-idempotent.sh` and `test-idempotent.env` and automatically runs:
1. **Idempotent test variant** (with cleanup)
2. **Regular test** (with EXIT trap cleanup)

### Test Flow

**Idempotent Test:**
1. Creates a component (triggers build)
2. Waits for automatic Release-1 (created by Konflux when build completes)
3. Release-1 completes successfully (pushes images to registry)
4. Extracts the snapshot name from Release-1
5. Creates Release-2 manually with the **same snapshot**
6. Release-2 should detect already-pushed images and filter/skip push
7. Verifies idempotency status and compares performance

**Regular Test:**
1. Runs the standard push-to-external-registry test flow
2. Validates basic release functionality

## Debugging

There is a `--skip-cleanup` option to the script in the event that you want to examine the resources after a test has ended.

```shell
../run-test.sh push-to-external-registry --skip-cleanup
```

This will skip cleanup for the last test variant (regular test), allowing you to inspect resources.

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

## Expected Results

### When Idempotency is Working:
```
Test Results Summary:
   Release-1 (initial):    150s
   Release-2 (repeat):     45s
   Idempotency Status:     WORKING
   Performance:            105s faster (70% improvement)

   ✅ PASS: Idempotency is working correctly!
```

### When Idempotency is Not Yet Implemented:
```
Test Results Summary:
   Release-1 (initial):    155s
   Release-2 (repeat):     143s
   Idempotency Status:     NOT WORKING
   Performance:            12s faster (7% improvement)

   ℹ️  INFO: Test completed successfully
   ⚠️  NOTE: Idempotency logic may need pipeline implementation
```

The test passes in both cases but reports the idempotency status for monitoring pipeline improvements.
