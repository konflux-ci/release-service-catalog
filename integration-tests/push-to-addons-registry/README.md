# Push to Addons Registry Test

This test validates the addon registry push pipeline functionality.

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
