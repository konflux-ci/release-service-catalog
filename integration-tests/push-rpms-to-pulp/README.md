# push-rpms-to-pulp Test

This test validates the push-rpms-to-pulp pipeline with two components:

- **Component A (hello)**: builds for all 4 architectures (x86_64, aarch64, s390x, ppc64le)
- **Component B (hello2)**: builds for x86_64 only

Both components produce binary, source, and noarch RPMs. The test verifies that each RPM is pushed to the correct Pulp repository and validates noarch fanout behavior.

Auto-release is disabled. The test waits for both component builds to complete, then manually creates a Release against the multi-component Snapshot. It also verifies idempotency by retriggering the release and checking that all RPMs are filtered as already published.

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
