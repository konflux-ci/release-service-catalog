# push-disk-images-to-marketplaces E2E Test

Integration test for the `push-disk-images-to-marketplaces` managed pipeline, which exercises the
`marketplacesvm-push-disk-images` task to publish VM disk images to cloud marketplaces (AWS, Azure).

## Status

This test is currently **optional** (`test.appstudio.openshift.io/optional: 'true'`). It will be
promoted to required once the stage infrastructure is in place (marketplace credentials, starmap
mappings) and the vault secrets are set up.

## What it tests

Registers two Konflux Components under one Application, waits for both builds, then creates a
Release against the multi-component Snapshot. That exercises `marketplacesvm-push-disk-images`
with two disk images in a single TaskRun (the pipeline default `concurrentLimit` is 3, so both
components run in one wave). The suite verifies the Snapshot has both components and the TaskRun
succeeds with both names in the logs.

### How the test image is built

Each Konflux `Component` builds with `docker-build-oci-ta`. Before merge, the suite replaces the
`Dockerfile` on each component pull request with `resources/tenant/templates/Dockerfile`, which
creates a 1GiB sparse raw disk with a DOS MBR at `/releases/test-disk-image.raw`. The builds are
signed and attested. `resources/tenant/rp.yaml` uses `auto-release: 'false'` so the Release is
created only after both components are in the Snapshot.

The `marketplacesvm-push-disk-images` task then:
1. Pulls the image with `oras pull` (flat OCI artifacts unpack here)
2. If the mapped file is still missing, extracts it from image layers with `skopeo` + `tar`
3. Validates the files match expected formats (.raw for AWS, .vhd for Azure)
4. Runs `pubtools-marketplacesvm` against the configured marketplace mapping

## Infrastructure requirements

Before this test can run, the following must be in place:

### Cloud marketplace secrets in managed namespace

The suite vault creates `marketplacesvm-test-secret-${component_name}` in
`managed-release-team-tenant`. Each key is a JSON file with `marketplace_account` and `auth`:
https://release-engineering.github.io/pubtools-marketplacesvm/common/credentials.html#auth-format

### Starmap mapping configuration

The `ReleasePlanAdmission` includes `starmap` mapping configuration for both test components,
defining which marketplaces and regions to publish to. With `cloudMarketplacesPrePush: "true"`,
the test performs a pre-push (dry run) that does not publish to production marketplaces.

## Vault files

The `vault/` files must be ansible-vault encrypted before committing:

```bash
ansible-vault encrypt vault/tenant-secrets.yaml vault/managed-secrets.yaml
```

These contain the GitHub PAC token, dockerconfigjson, and marketplace credentials.

## Jira

[RELEASE-2344](https://redhat.atlassian.net/browse/RELEASE-2344)
