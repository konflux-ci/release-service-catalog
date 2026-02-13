# rh-advisories-large-snapshot test

## Overview
This test simulates an OpenShift release workflow with 200 large, multi-architecture components:
- **Image sizes**: Random 300 MB - 1.5 GB per architecture
- **Architectures**: 4 platforms (amd64, arm64, s390x, ppc64le)
- **Total digests**: ~800 (200 components × 4 archs)
- **Expected duration**: 11-14 hours (build + signing)
- **Total data**: ~720 GB of image data

Each component gets a unique branch with custom Dockerfile - all fully automated.

## Image Size Limitations

**Important**: Image sizes are constrained to 300 MB - 1.5 GB per architecture due to build resource limitations.

### Why this limit exists:
- **Memory constraints**: The Konflux build pods have limited memory available during image builds
- **Buildah commit phase**: When `buildah` commits an image, it needs substantial memory to:
  - Process all image layers
  - Compress the final image
  - Push to the registry
- **OOM kills observed**: Images larger than 1.5 GB consistently trigger Out-Of-Memory (OOM) kills during the commit phase

### What we tested:
- ❌ **1-5 GB images**: Build process killed during commit (`exit status 1`, process terminated by kernel)
- ❌ **500 MB - 5 GB images**: Larger images (>2 GB) still hit OOM during commit
- ✅ **300 MB - 1.5 GB images**: Stable builds, no OOM kills, adequate stress testing

### Why this is still effective:
- **Total data volume**: ~720 GB across 800 images (100 components × 4 archs × ~900 MB avg)
- **Realistic scale**: Matches production OpenShift release scenarios
- **Multi-arch complexity**: 4 architectures per component provides adequate stress on signing/advisory services
- **Signing performance**: The constraint is signing time, not image size—more smaller images is equivalent

### Increasing the limit:
To use larger images, you would need to:
1. Increase memory limits in `.tekton/` PipelineRun definitions (currently uses default limits)
2. Request larger build nodes from cluster admins
3. Or optimize the Dockerfile to reduce peak memory usage during build

## Setup
### Dependencies
* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for above repo with **admin:repo_hook**, **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you want to run this
  test suite.)
* Access to the target cluster and tenant and managed namespaces
  * This test uses stg-rh01 and the dev-release-team-tenant and managed-release-team-tenant namespaces.

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
- Since this test requires internal services, the tenant and managed namespaces
  should remain as-is.
#### [test.sh](test.sh)
- This file contains specific variables and functions needed for the test.
### Test Functions
#### [lib/test-functions.sh](../lib/test-functions.sh)
- This file contains re-usable functions for tests
### Secrets
- Secrets needed for testing are stored in ansible vault files.
  - [vault/managed-secrets.yaml](vault/managed-secrets.yaml)
  - [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml)
- The secrets required are contained in the files above.
### Running the test

```shell
../run-test.sh rh-advisories-large-snapshot
```

### Debugging

There is a `--skip-cleanup` option to the script in the event that you want to examine the resources
after a test has ended.
