# push-disk-images E2E Test

Integration test for the `push-disk-images-to-cdn` managed pipeline, which exercises the
`push-disk-images` internal pipeline and the `pulp-push-disk-images` task.

## Status

This test is currently **optional** (`test.appstudio.openshift.io/optional: 'true'`). It will be
promoted to required once the stage infrastructure is in place (Pulp repo, CGW destination) and
the vault secrets and test OCI image are set up.

## What it tests

Triggers a full release through `push-disk-images-to-cdn` on the stage cluster and verifies
that the `push-disk-images` TaskRun inside the managed PipelineRun succeeds.

## Infrastructure requirements

Before this test can run, the following must be in place:

### Test OCI image

A test OCI artifact must be pushed to `quay.io/hacbs-release-tests/push-disk-images-base`
(or a similar public repo). The OCI image must contain a file matching the `staged.files[].source`
value in `resources/managed/rpa.yaml` (currently `test-disk-image.raw`).

A minimal test image can be created and pushed with:

```bash
echo "test disk image content" > test-disk-image.raw
oras push quay.io/hacbs-release-tests/push-disk-images-base:latest test-disk-image.raw
```

Then create the base branch in `hacbs-release-tests/e2e-base` or a dedicated repo that Konflux
can build from. Update `component_base_branch` in `test.env` accordingly.

### CDN secrets in managed namespace

With `cdn.env: qa` in `rpa.yaml`, the `push-disk-images` managed task expects these secrets
to exist in `managed-release-team-tenant`:

| Secret name | Keys |
|---|---|
| `exodus-stage-secret` | `cert`, `key`, `url` |
| `rhsm-pulp-qa-secret` | `konflux-release-rhsm-pulp.crt`, `konflux-release-rhsm-pulp.key`, `pulp_url` |
| `udcache-stage-secret` | `cert`, `key`, `url` |
| `cgw-service-account-stage-secret` | `username`, `token` |

These are pre-existing cluster-wide secrets (not created per test run). Confirm they exist with:

```bash
kubectl get secret exodus-stage-secret rhsm-pulp-qa-secret udcache-stage-secret \
  cgw-service-account-stage-secret -n managed-release-team-tenant
```

### Pulp destination

The `staged.destination` in `rpa.yaml` (`push-disk-images-e2e-test`) must resolve to a valid
Pulp repository path accessible with the `rhsm-pulp-qa-secret` credentials.

### Stage CDN/Exodus access

The Exodus Gateway and UDCache endpoints must be reachable from the stage cluster.

## Vault files

The `vault/` files must be ansible-vault encrypted before committing:

```bash
ansible-vault encrypt vault/tenant-secrets.yaml vault/managed-secrets.yaml
```

Fill in the actual values (GitHub PAC token, dockerconfigjson) before encrypting.

## Jira

[RELEASE-2699](https://redhat.atlassian.net/browse/RELEASE-2699)
