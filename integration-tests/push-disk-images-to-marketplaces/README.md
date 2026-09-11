# push-disk-images-to-marketplaces E2E Test

Integration test for the `push-disk-images-to-marketplaces` managed pipeline, which exercises the
`marketplacesvm-push-disk-images` task to publish VM disk images to cloud marketplaces (AWS, Azure).

## Status

This test is currently **optional** (`test.appstudio.openshift.io/optional: 'true'`). It will be
promoted to required once the stage infrastructure is in place (marketplace credentials, starmap
mappings) and the vault secrets are set up.

## What it tests

Triggers a full release through `push-disk-images-to-marketplaces` on the stage cluster and verifies
that the `marketplacesvm-push-disk-images` TaskRun inside the managed PipelineRun succeeds.

### How the test image is built

The Konflux `Component` builds with `docker-build-oci-ta`. Before merge, the suite replaces the
component `Dockerfile` with `resources/tenant/templates/Dockerfile`, which creates a 1GiB sparse
raw disk with a DOS MBR at `/releases/test-disk-image.raw`. The build is signed and attested;
`resources/tenant/rp.yaml` uses `auto-release: 'true'`.

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

The `ReleasePlanAdmission` includes `starmap` mapping configuration for the test component,
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
