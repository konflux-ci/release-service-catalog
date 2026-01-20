# Shared Integration Test Resources

This directory contains shared resources and configuration used by integration test suites. It helps reduce code duplication and ensures consistent behavior across tests.

## Directory Structure

```
shared/
├── base-test.env           # Common environment variables
├── README.md               # This file
└── resources/
    ├── tenant/             # Shared tenant namespace resources
    │   ├── application.yaml
    │   ├── component.yaml
    │   ├── rp.yaml
    │   └── kustomization.yaml
    └── managed/            # Shared managed namespace resources
        ├── ec-policy.yaml
        └── kustomization.yaml
```

**Note:** ServiceAccount (`sa.yaml`) and RoleBinding (`sa-rolebinding.yaml`) files are NOT shared because each test requires test-specific secrets in the ServiceAccount.

## Usage

### For Test Suites

Test suites use shared resources through Kustomize overlays. Each test's `kustomization.yaml` references shared resources:

```yaml
# resources/tenant/kustomization.yaml
resources:
  - ../../../shared/resources/tenant
  - secrets/tenant-secrets.yaml
```

**Note:** Kustomize is invoked with `--load-restrictor=LoadRestrictionsNone` to allow loading resources from outside the test directory.

### For Environment Variables

The `base-test.env` file is sourced by `run-test.sh` after the test-specific `test.env`. It provides:

1. **Namespace configuration** - Standard tenant/managed namespaces
2. **GitHub configuration** - Common org and repo settings
3. **Computed defaults** - Component names, URLs, and service accounts via `finalize_test_env()`

## Test Environment Structure

Each test's `test.env` must include UUID generation and essential variables for cleanup compatibility:

```bash
# UUID Generation (required for cleanup step)
uuid=${uuid:-"$(openssl rand -hex 4)"}
uuid="${uuid:0:8}"

# Test-specific configuration
export originating_tool="my-test-e2e-test"
export component_type="my-test"
export component_base_branch="my-test-base"

# Optional: Override application name prefix
export application_name_prefix="my"

# Essential computed variables (required for cleanup step)
export component_github_org=hacbs-release-tests
export component_name="${component_type}-${uuid}"
export component_repo_name="${component_github_org}/${component_name}"
```

### Post-Init Functions

Tests with complex dependencies can define a post-init function:

```bash
# Called after finalize_test_env() by run-test.sh
_post_init_my_test() {
    export additional_var="value-${uuid}"
}
```

## Shared Resources

### application.yaml
Standard Application resource template with environment variable substitution.

### component.yaml
Standard Component resource with GitHub integration and PAC configuration.

### rp.yaml
Standard ReleasePlan with auto-release and standing attribution.

### ec-policy.yaml
EnterpriseContractPolicy with SLSA3 compliance rules.

## Customization

Tests use shared resources through Kustomize overlays, always providing their own SA files:

### Standard Test Pattern
For tests using shared application, component, and rp:

```yaml
resources:
  - ../../../shared/resources/tenant  # application, component, rp
  - sa.yaml                           # Local SA (test-specific secrets)
  - sa-rolebinding.yaml               # Local RoleBinding
  - secrets/tenant-secrets.yaml
```

### Custom Component
For tests needing custom components (e.g., push-rpms-to-pulp, fbc-release):

```yaml
resources:
  - ../../../shared/resources/tenant/application.yaml
  - component.yaml                    # Custom component
  - sa.yaml
  - sa-rolebinding.yaml
  - ../../../shared/resources/tenant/rp.yaml
  - secrets/tenant-secrets.yaml
```

### Fully Custom
For tests with extensive customizations (e.g., collectors):

```yaml
resources:
  - ../../../shared/resources/tenant/application.yaml
  - component.yaml                    # Custom component
  - sa.yaml
  - sa-rolebinding.yaml
  - rp.yaml                           # Custom RP with Jira templates
  - secrets/tenant-secrets.yaml
```

## Tests With Special Requirements

| Test | Custom Resources |
|------|-----------------|
| collectors | Custom naming, two SAs, Jira templates in RP |
| fbc-release | Custom component (FBC-builder), multiple release plans |
| push-rpms-to-pulp | Custom component (multi-platform builds) |

