# Push to Addons Registry Test

This test validates the addon registry push pipeline functionality.

The Konflux build is configured for a **multi-arch manifest list** (amd64 and arm64), matching common OSD addon index images.
**Note:** This test patches the component’s PaC templates in the PR *before merge* to ensure the `build-platforms` param 
includes `linux/amd64` and `linux/arm64`, so the push pipeline produces a multi-arch index for verification.
## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values specific to addon registry push
- **`test.sh`** - Contains addon registry-specific variables and functions for the test

## Running the Test

```bash
../run-test.sh push-to-addons-registry
```

## Test Workflow

The addon registry push test follows this specific workflow:

1. **Addon Registry Setup** - Prepares addon registry configurations
2. **Addon Package Preparation** - Creates addon packages and metadata
3. **Registry Push Pipeline Execution** - Executes the addon registry push pipeline
4. **Registry Verification** - Validates successful addon registration and availability
