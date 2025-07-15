# FBC Release Test

This test validates the File-Based Catalog (FBC) release pipeline functionality.

## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values specific to FBC releases
- **`test.sh`** - Contains FBC-specific variables and functions for the test

## Running the Test

```bash
../run-test.sh fbc-release
```

## Test Workflow

The FBC release test follows this specific workflow:

1. **FBC Catalog Setup** - Prepares File-Based Catalog resources
2. **Release Pipeline Execution** - Executes the FBC release pipeline
3. **Catalog Validation** - Validates the generated catalog structure
4. **Release Verification** - Confirms successful FBC release deployment
