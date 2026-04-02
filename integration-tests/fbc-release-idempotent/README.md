# fbc-release-idempotent test

Integration test that validates the idempotency behavior of the `filter-published-fbc-images`
task within the `fbc-release` pipeline. The test creates two releases from the same snapshot
and verifies that the second release correctly detects the already-published index image in
Pyxis using the `repositories.*` filter fields.

## Setup

### Dependencies

* GitHub repo: https://github.com/hacbs-release-tests/e2e-base
* GitHub personal access token (classic) for the above repo with **admin:repo_hook**,
  **delete_repo**, **repo** scopes.
* The password to the vault files. (Contact a member of the Release team should you want to
  run this test suite.)
* Access to the target cluster and the tenant and managed namespaces.
  * This test uses stg-rh01 and the dev-release-team-tenant and managed-release-team-tenant
    namespaces.

### Required Environment Variables

- `GITHUB_TOKEN`
  - The GitHub personal access token needed for repo operations.
  - The repo in question can be located in [test.env](test.env).
- `VAULT_PASSWORD_FILE`
  - Path to a file that contains the Ansible Vault password needed to decrypt the secrets
    required for testing.
- `RELEASE_CATALOG_GIT_URL`
  - The release-service-catalog URL to use in the RPA.
  - This is provided when testing PRs.
- `RELEASE_CATALOG_GIT_REVISION`
  - The release-service-catalog revision to use in the RPA.
  - This is provided when testing PRs.

### Optional Environment Variables

- `KUBECONFIG`
  - The KUBECONFIG file to use to log in to the target cluster.
  - This is provided when testing PRs.

### Test Properties

#### [test.env](test.env)

This file contains resource names and configuration values needed for testing, including a
unique UUID-based suffix to avoid name collisions with other test runs.

### Test Functions

#### [lib/test-functions.sh](../lib/test-functions.sh)

This file contains re-usable functions shared across all integration tests.

### Secrets

Secrets required for testing are stored in Ansible Vault files. The vault files in this
test symlink to the credentials in the sibling `fbc-release` test:

- [vault/managed-secrets.yaml](vault/managed-secrets.yaml) → `../fbc-release/vault/managed-secrets.yaml`
- [vault/tenant-secrets.yaml](vault/tenant-secrets.yaml) → `../fbc-release/vault/tenant-secrets.yaml`

## Running the Test

```shell
integration-tests/run-test.sh fbc-release-idempotent --no-cve --skip-cleanup
```

## Test Workflow

### Phase 1 — First Release

1. A fresh FBC component is released through the `fbc-release` pipeline.
2. `filter-published-fbc-images` runs; Pyxis returns no index image (first release) so all
   components are kept.
3. `add-fbc-contribution-to-index-image` runs and publishes the index image.
4. `create-pyxis-image` registers the index image in Pyxis (identified by
   `repositories.registry`, `repositories.repository`, and `repositories.tags.name`).

### Phase 2 — Second Release (same snapshot)

1. A second `Release` CR is created pointing to the exact same snapshot.
2. `filter-published-fbc-images` queries Pyxis using the correct `repositories.*` filter.
3. Pyxis returns the previously published index image (`data` array is non-empty).
4. If the index image record contains fragment digest data (`related_images` / `bundles`),
   matching components are filtered out and `add-fbc-contribution-to-index-image` is skipped.

### Known Limitation

The Pyxis `ContainerImage` schema does not store fragment digests inside the index image
record (`related_images` and `bundles` are OLM concepts not natively present in Pyxis). Until
fragment digests are separately registered in Pyxis (or an alternative detection mechanism is
added), Phase 2 confirms that the **Pyxis query uses the correct filter fields** and that the
index image is found, but cannot assert that individual fragments are filtered. The task falls
back safely to keeping all components when fragment digest data is absent.

## Debugging

Use `--skip-cleanup` to preserve all Kubernetes resources after the test run for inspection:

```shell
integration-tests/run-test.sh fbc-release-idempotent --no-cve --skip-cleanup
```

## Maintenance

Should you need to add or update a secret, the vault files are symlinked from `fbc-release`.
Edit the originals there:

```shell
ansible-vault decrypt ../fbc-release/vault/tenant-secrets.yaml \
  --output /tmp/tenant-secrets.yaml \
  --vault-password-file <vault-password-file>
vi /tmp/tenant-secrets.yaml
ansible-vault encrypt /tmp/tenant-secrets.yaml \
  --output ../fbc-release/vault/tenant-secrets.yaml \
  --vault-password-file <vault-password-file>
rm /tmp/tenant-secrets.yaml
```

## Related

- [RELEASE-2379](https://redhat.atlassian.net/browse/RELEASE-2379) — bug: `docker_image_id`
  filter returns empty results from Pyxis
- [`tasks/managed/filter-published-fbc-images/`](../../tasks/managed/filter-published-fbc-images/) — the task under test
- [`integration-tests/fbc-release/`](../fbc-release/) — base FBC release test this test extends
