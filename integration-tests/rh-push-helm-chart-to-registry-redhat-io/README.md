# rh-push-helm-chart-to-registry-redhat-io e2e test

End-to-end test for the [`rh-push-helm-chart-to-registry-redhat-io`](../../pipelines/managed/rh-push-helm-chart-to-registry-redhat-io/README.md) release pipeline.

## How it works

1. A Helm chart source repo is cloned from `hacbs-release-tests/e2e-base` branch `rh-push-helm-chart-to-registry-redhat-io-base`.
2. Konflux builds the chart using a custom Helm OCI build pipeline (bundled separately).
3. The release pipeline validates the Helm chart snapshot, pushes to the staging registry, creates Pyxis entries, and signs.
4. `test.sh` verifies the release artifacts are accessible via skopeo.

## Build pipeline bundle (temporary)

Since `build-helm-chart-oci-ta` is not yet in the cluster `build-pipeline-config`, we use a custom
pipeline bundle. **This is temporary** — once the build team publishes an official
`build-helm-chart-oci-ta` pipeline, this bundle and the custom annotation in `component.yaml`
should be removed in favour of the cluster-provided pipeline.

The pipeline YAML is at [`resources/build/helm-chart-build-pipeline.yaml`](resources/build/helm-chart-build-pipeline.yaml).

To push or update the bundle:

```bash
tkn bundle push quay.io/swickers/pipeline-build-helm-chart-oci-ta:latest \
  -f integration-tests/rh-push-helm-chart-to-registry-redhat-io/resources/build/helm-chart-build-pipeline.yaml
```

The component annotation in [`resources/tenant/component.yaml`](resources/tenant/component.yaml) references this bundle directly.

## Component naming and parallel runs

The Kubernetes Component name is UUID-suffixed (`caching-helm-test-rhel9-<uuid>`)
like other e2e tests, allowing parallel runs. However, the OCI image **basename**
must remain `caching-helm-test-rhel9` because:

- `validate-helm-chart-snapshot` checks that the OCI `org.opencontainers.image.title` matches the delivery repo basename
- `publish-pyxis-repository` requires the delivery repo to already exist in Pyxis stage
- The Pyxis repo (`dev-release-team-tenant/caching-helm-test-rhel9`) is defined in [pyxis-repo-configs](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/blob/main/products/test-helm/caching-helm-test.yaml)

To decouple the K8s name from the image basename, the test uses two mechanisms:

1. **Explicit `spec.containerImage`** on the Component, with a path whose
   basename is always `caching-helm-test-rhel9`.
2. **An `ImageRepository` CR** that tells the Konflux image controller to
   create the quay repo at the exact path we specify and generate push
   credentials for the build SA — without overriding `containerImage`.

Each parallel run creates its own quay repo (keyed by the UUID application
name) with the same fixed basename. The build task derives the OCI title
from this basename, not from the Component CR name.


## Prerequisites

- `hacbs-release-tests/e2e-base` branch `rh-push-helm-chart-to-registry-redhat-io-base` must exist with Helm chart source
- The build pipeline bundle must be pushed to `quay.io/swickers/pipeline-build-helm-chart-oci-ta:latest`
- Pyxis repo `dev-release-team-tenant/caching-helm-test-rhel9` must exist in Pyxis stage
- Standard e2e secrets: `GITHUB_TOKEN`, `VAULT_PASSWORD_FILE`, `RELEASE_CATALOG_GIT_URL`, `RELEASE_CATALOG_GIT_REVISION`
- Cluster access to staging (`dev-release-team-tenant` / `managed-release-team-tenant`)

## Running

```bash
cd integration-tests
./run-test.sh rh-push-helm-chart-to-registry-redhat-io
```

Use `--skip-cleanup` to keep resources for debugging.
