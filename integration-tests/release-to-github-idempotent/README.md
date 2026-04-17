# Release to GitHub Idempotent Test

This test validates the idempotent retrigger behavior of the `release-to-github` pipeline when the same
snapshot is released a second time.

## Test Workflow

1. **First Release** - A GitHub release is created at tag `v86.${uuid}`, the SHA256SUMS file is signed,
   and an advisory is created. The release completes with `Released=True`.

2. **Second Release (Retrigger)** - A second Release CR is created manually using the **same snapshot**.
   The pipeline runs again but:
   - `create-github-release` detects the existing GitHub release at `v86.${uuid}` and skips creation
   - `sign-base64-blob` re-signs the blob (its internal skip-if-sig-exists logic applies to
     within-run retries only; each new pipeline run starts with a fresh Trusted Artifacts workspace
     so no `.sig` file is present at the start of the run)

3. **Verification** - The test asserts:
   - Second release completes successfully with `Released=True`
   - Same GitHub release URL is returned on both runs
   - No duplicate GitHub release is created — `create-github-release` skips uploading to the existing release
   - GitHub release assets are identical after both runs (no extra files uploaded)

## Running the Test

```bash
../run-test.sh release-to-github-idempotent
```

## Files Structure

- **`test.env`** - Resource names and configuration specific to this test suite
- **`test.sh`** - Test-specific functions implementing the idempotent verification logic
- **`resources/`** - Kubernetes resource templates (mirrors `release-to-github` resources)
- **`vault/`** - Symlinks to `release-to-github/vault/` (same secrets are used)
