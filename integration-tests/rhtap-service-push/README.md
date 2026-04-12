# RHTAP Service Push Test

This test validates the RHTAP service push pipeline functionality.

## Test-Specific Dependencies

In addition to the [common dependencies](../README.md#dependencies), this test requires:

* **GitHub Repository**: https://github.com/hacbs-release/infra-deployments

## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values specific to RHTAP service push
- **`test.sh`** - Contains RHTAP service push-specific variables and functions for the test

## Running the Test

```bash
../run-test.sh rhtap-service-push
```

## Test Workflow

The RHTAP service push test follows this specific workflow:

1. **RHTAP Service Setup** - Prepares RHTAP service configurations
2. **Infra-Deployments Integration** - Integrates with infra-deployments repository
3. **Service Push Pipeline Execution** - Executes the RHTAP service push pipeline
4. **Deployment Verification** - Validates successful service deployment and updates

### Release Verification Checks

`verify_release_contents()` asserts the following for each Release:

- **`image_url`** - non-empty; the published image URL is present in the Release status
- **`image_shasum`** - non-empty; the image digest is recorded in the Release status
- **Skopeo inspect** - `skopeo inspect` succeeds on the digest pullspec (`<registry>/<repo>@<shasum>`), confirming the image is actually pullable from the target registry
- **Infra-deployments PR** - a pull request touching `components/release/development/kustomization.yaml` exists in `hacbs-release/infra-deployments` for the released git revision
