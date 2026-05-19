# push-rpms-to-pulp Test

This test validates the push-rpms-to-pulp pipeline with two components:

- **Component A (hello)**: multi-arch binaries (x86_64, aarch64, s390x, ppc64le) plus a noarch subpackage
- **Component B (hello2)**: noarch-only — only `*.noarch.rpm` and `*.src.rpm` (no arch-specific binaries)

hello2 was simplified from a x86_64 binary package to a data-only noarch spec so the E2E can verify a noarch-only component in a multi-component release: hello2 publishes only `*.noarch.rpm` and `*.src.rpm`, and `hello2.noarch` is fanned out to all four binary repos (hello already supplies the arch repos).

Auto-release is disabled. The test waits for both builds, creates a Release from the multi-component Snapshot, then retriggering it to confirm already-published RPMs are filtered (`skip_release=true`).

## Test-Specific Dependencies

- A pulp domain is required for these tests. One has already been created. It is called `konflux-release-integration-tests`
- In the event that you need to recreate it, a helper script is available.
  - See `integration-tests/push-rpms-to-pulp/utils/README.md`

## Test-Specific Secrets

This test uses specialized vault files with different naming:

- **`vault/managed-secrets.yaml`** - Secrets for the managed namespace
- **`vault/tenant-secrets.yaml`** - Secrets for the tenant namespace

## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values
- **`test.sh`** - Contains test-specific variables and functions

### Overriding Build Pipelines

Due to the type of artifact being built ... rpms ... we need to override what is proposed by Konflux as a build template. Therefore, the `patch_component_source_before_merge()` method is overidden to use:

- integration-tests/push-rpms-to-pulp/resources/tenant/templates/tekton/pull-request-template.yaml
- integration-tests/push-rpms-to-pulp/resources/tenant/templates/tekton/push-template.yaml

as the source for the PR that Konflux is being proposed for the onboarding step.
