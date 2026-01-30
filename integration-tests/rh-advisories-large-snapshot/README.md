# rh-advisories-large-snapshot test

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

**IMPORTANT:** The namespace difference between PaC and local runs is intentional:
- PaC runs in `rhtap-release-2-tenant` where the PipelineRun is created
- Local test runs default to `dev-release-team-tenant` for isolation
- Both namespaces must have the required secrets configured

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
- DEFAULT_CONSOLE_URL
  - Default OpenShift console URL (defaults to stg-rh01 staging cluster)
  - Override to use a different cluster console for PipelineRun links
  - Default: `https://console-openshift-console.apps.stone-stg-rh01.l2vh.p1.openshiftapps.com`
- CONSOLE_URL
  - OpenShift console URL for generating PipelineRun links
  - Auto-detected from PaC ConfigMap, falls back to DEFAULT_CONSOLE_URL
  - Override for custom cluster console URLs

### Test Properties
#### [test.env](test.env)
- This file contains resource names and configuration values needed for testing.
- This test creates a large snapshot with pre-built components to test advisory creation at scale.
- The component count is configurable via `LARGE_SNAPSHOT_COMPONENT_COUNT` (default: 200).
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

### Running the test

This test can be triggered manually via PR comment:

```
/test-large-snapshot
```

Comment on any PR. The PaC configuration ([.tekton/rh-advisories-large-snapshot.yaml](../../.tekton/rh-advisories-large-snapshot.yaml)) 
will trigger the Tekton pipeline automatically.

The pipeline runs in the cluster and uses existing Kubernetes secrets (vault-password-secret, github-token-secret, kubeconfig-secret).

For local testing:

```shell
../run-test.sh rh-advisories-large-snapshot
```

**Note:** This test takes 4-8 hours to complete due to processing a large number of components (default: 200).

#### Namespace Configuration for Local Runs

By default, local test runs use `dev-release-team-tenant` as the tenant namespace (see [test.env](test.env)).

To override the tenant namespace for local testing (e.g., to match PaC behavior):

```shell
export tenant_namespace=rhtap-release-2-tenant
../run-test.sh rh-advisories-large-snapshot
```

**Prerequisites for using a different tenant namespace:**
- The namespace must exist on the target cluster
- Required secrets must be configured: `vault-password-secret`, `github-token-secret`, `kubeconfig-secret`
- Your ServiceAccount must have permissions to create resources in both tenant and managed namespaces
- The ReleasePlanAdmission must be configured in the managed namespace

### Debugging

There is a `--skip-cleanup` option to the script in the event that you want to examine the resources
after a test has ended.

### Maintenance

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
