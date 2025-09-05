# FBC Release Multi-Component Test

This test validates the File-Based Catalog (FBC) release pipeline functionality with multiple components to verify IIB batching behavior.

## Test Overview

This integration test creates a multi-component FBC release scenario that exercises the IIB batching functionality introduced to optimize FBC fragment processing. The test validates that:

1. Components with the same batching criteria are processed together in a single IIB batch
2. All components appear correctly in the final release artifacts  
3. The batching logic works end-to-end in a realistic scenario

## Test Scenarios

### Batching Scenario: Same Batching Criteria (Components 1 & 2)
- **Component 1**: `context: "4.13"` (OCP version v4.13)
- **Component 2**: `context: "4.13"` (OCP version v4.13)
- **Expected Behavior**: These components should be batched together in a single InternalRequest because they have identical batching criteria (same OCP version, same fromIndex, targetIndex, buildTags, addArches)

## Test Structure

```
integration-tests/fbc-release-multi-component/
├── README.md                    # This documentation
├── test.sh                      # Enhanced verification logic for multi-component scenarios
├── test.env                     # Environment variables for 2 components
├── resources/
│   ├── tenant/
│   │   ├── kustomization.yaml   # References both components
│   │   ├── application.yaml     # Single application for all components
│   │   ├── component1.yaml      # Component with context "4.13"
│   │   ├── component2.yaml      # Component with context "4.13" (batches with component1)
│   │   ├── sa.yaml              # Service account
│   │   ├── sa-rolebinding.yaml  # Service account permissions
│   │   └── rp.yaml              # Release plans
│   └── managed/
│       ├── kustomization.yaml   # Managed resources
│       ├── rpa.yaml             # Release plan admission
│       ├── ec-policy.yaml       # Enterprise contract policy
│       ├── sa.yaml              # Managed service account
│       └── sa-rolebinding.yaml  # Managed service account permissions
└── vault/
    ├── tenant-secrets.yaml      # Encrypted tenant secrets
    └── managed-secrets.yaml     # Encrypted managed secrets
```

## Key Validation Points

The enhanced `verify_release_contents()` function validates:

### Component Presence
- Verifies exactly 3 components are present in `.status.artifacts.components[]`
- Confirms all expected component names are found
- Validates each component has required fields (fbc_fragment, ocp_version, iibLog)

### Batching Behavior Verification
- **Components 1 & 2**: Both have `ocp_version: "v4.13"` indicating they shared batching criteria
- **Component 3**: Has `ocp_version: "v4.14"` indicating it was processed separately
- Validates that the IIB batching logic correctly grouped components by criteria

### Release Artifacts
- Confirms all components have valid FBC fragments
- Verifies IIB logs are present for all components
- Validates index_image and index_image_resolved fields are populated

## Running the Test

```bash
../run-test.sh fbc-release-multi-component
```

## Test Workflow

1. **Multi-Component Setup** - Creates 1 application with 3 FBC components
2. **Component Processing** - Each component triggers its own build pipeline
3. **Release Pipeline Execution** - Single release processes all 3 components
4. **Batching Verification** - Validates that batching occurred correctly:
   - Components 1 & 2 were batched together (same OCP version)
   - Component 3 was processed separately (different OCP version)
5. **Artifact Validation** - Confirms all components appear in final release

## Expected Batching Behavior

When the `add-fbc-contribution` task processes the snapshot:
1. **Batching Analysis**: Groups components by `fromIndex + targetIndex + buildTags + addArches + ocpVersion`
2. **Batch 1**: Components 1 & 2 (both v4.13) → Single InternalRequest with `fbcFragments` array
3. **Batch 2**: Component 3 (v4.14) → Separate InternalRequest with single-element `fbcFragments` array
4. **IIB Processing**: Each batch calls IIB API with appropriate `fbc_fragments` parameter
5. **Result Aggregation**: Both batches' results are combined in final release artifacts

This test ensures that the IIB batching feature works correctly in realistic multi-component scenarios while maintaining backward compatibility for single-component releases.