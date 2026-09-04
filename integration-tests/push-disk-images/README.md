# push-disk-images E2E Test

Integration test for the `push-disk-images-to-cdn` managed pipeline, which exercises the
`push-disk-images` internal pipeline and the `pulp-push-disk-images` task.

## Status

This test is currently **optional** (`test.appstudio.openshift.io/optional: 'true'`). It will be
promoted to required once the stage infrastructure is in place (Pulp repo, CGW destination) and
the vault secrets are set up, and this fixture change has a clean e2e run.

## What it tests

Triggers a full release through `push-disk-images-to-cdn` on the stage cluster and verifies
that the `push-disk-images` TaskRun inside the managed PipelineRun succeeds.

### How the test image is built

Production disk-image references are flat, single-blob **OCI artifacts** — exactly what
`bootc-image-builder` produces via `buildah manifest add --artifact` — which the internal
`pulp-push-disk-images` task pulls with a plain `oras pull`. Earlier revisions of this test
tried to mimic that by manually `oras push`-ing a fake artifact with no Konflux build behind
it, which meant it had no real signature/attestation and failed `verify-conforma`'s
non-excludable `builtin.attestation.signature_check` / `builtin.image.signature_check` rules
(see [RELEASE-1990](https://redhat.atlassian.net/browse/RELEASE-1990)).

This test now follows the same "Component 3" pattern `push-artifacts-to-cdn`'s e2e test uses
for its own disk-image content type: the Konflux `Component` in
`resources/tenant/component.yaml` builds normally via `docker-build-oci-ta` (Dockerfile in the
`hacbs-release-tests/e2e-base` `push-disk-images-base` branch), which just does
`COPY releases/ /releases/` to place `releases/test-disk-image.raw` in the image. Because it's
a real Konflux build, the resulting image gets a genuine cosign signature and attestation, and
`resources/tenant/rp.yaml` uses normal `auto-release: 'true'` — no manual Snapshot/Release
juggling needed.

To pull the file back out on the managed side, `pulp_push_disk_images.py`
(`release-service-utils`) first tries the flat-artifact `oras pull` path (used in production);
if the wanted file isn't found that way, it falls back to `oras_utils.extract_disk_image_files`,
which pulls via `skopeo` and extracts the file from the image's tar layers instead — the same
dual-mode approach `extract_artifacts.py` already uses for `push-artifacts-to-cdn`. Production's
behavior (and callers of `oras_pull` elsewhere) is unchanged; this only adds a new fallback path.

## Infrastructure requirements

Before this test can run, the following must be in place:

### CDN secrets in managed namespace

With `cdn.env: stage` in `rpa.yaml`, the `push-disk-images` managed task expects these secrets
to exist in `managed-release-team-tenant` (same ones `push-artifacts-to-cdn`'s stage e2e test
already relies on):

| Secret name | Keys |
|---|---|
| `exodus-prod-secret` | `cert`, `key`, `url` |
| `rhsm-pulp-stage-secret` | `konflux-release-rhsm-pulp.crt`, `konflux-release-rhsm-pulp.key`, `pulp_url` |
| `udcache-stage-secret` | `cert`, `key`, `url` |
| `cgw-service-account-stage-secret` | `username`, `token` |

These are pre-existing cluster-wide secrets (not created per test run). Confirm they exist with:

```bash
kubectl get secret exodus-prod-secret rhsm-pulp-stage-secret udcache-stage-secret \
  cgw-service-account-stage-secret -n managed-release-team-tenant
```

> Earlier revisions of this test used `cdn.env: qa`, pointing at
> `rhsm-pulp.corp.qa.redhat.com`. The `push-disk-images-e2e-test` Pulp repo was actually
> provisioned under the same `konflux-release-e2e` product family `push-artifacts-to-cdn`'s
> e2e test uses, which only exists on **stage** Pulp — so the `qa` env was pointed at a host
> that never had the repo, not a missing-provisioning issue. See RELEASE-2699 Slack thread.

### Pulp destination

The `staged.destination` in `rpa.yaml` (`push-disk-images-e2e-test`) must resolve to a valid
Pulp repository path accessible with the `rhsm-pulp-stage-secret` credentials.

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
