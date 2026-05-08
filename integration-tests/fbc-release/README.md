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

## Tested scenarios

The following scenarios are tested

### single component:
- single component happy path (`single-happy`)
- single component "staged" index (`single-staged`)
- single component Pre-GA index (`single-prega`)
- single component hotfix index (`single-hotfix`)
- single opt-in component happy path (`single-optin`)

### multi components:
- multi components happy path (`multi-happy`)
- multi components "staged" index (`multi-staged`)
- multi opt-in components happy path (`multi-optin`)

The resources/tenant/kustomization.yaml file contains the components required by these scenarios. Below is an explanation of which components are required by each scenario:

```
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${tenant_namespace}
resources:
  - application.yaml
  - component.yaml
  - component2.yaml
  - optin-component.yaml
  - multi-optin-component-1.yaml
  - multi-optin-component-2.yaml
  - sa.yaml
  - sa-rolebinding.yaml
  - rp.yaml
  - secrets/tenant-secrets.yaml
```

- `component.yaml` is used by all single scenarios (except opt-in¹)
- `component2.yaml` is used by multi-happy and multi-staged, both no opt-in components
- `optin-component.yaml` is used by `single-optin`
- `multi-optin-component-1.yaml` and `multi-optin-component-2.yaml`

*1. opt-in components are components with `fbc-opt-in` flag set to true in pyxis*
