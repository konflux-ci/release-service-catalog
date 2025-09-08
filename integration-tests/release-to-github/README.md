# Release to GitHub Test

This test validates the GitHub release pipeline functionality.

## Test-Specific Configuration

### Files Structure

- **`test.env`** - Contains resource names and configuration values specific to GitHub releases
- **`test.sh`** - Contains GitHub release-specific variables and functions for the test

## Running the Test

```bash
../run-test.sh release-to-github
```

## Test Workflow

The GitHub release test follows this specific workflow:

1. **GitHub Repository Setup** - Prepares target GitHub repository
2. **Release Asset Generation** - Creates release artifacts and checksums
3. **Release Pipeline Execution** - Executes the GitHub release pipeline
4. **Release Verification** - Validates the created GitHub release and assets
