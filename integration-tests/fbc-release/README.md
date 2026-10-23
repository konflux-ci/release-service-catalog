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

Which scenarios run is controlled by `PTSV_FBC_SCENARIOS` in `test.env` (a
space- or comma-separated list of scenario keys). When set, it enables exactly
those scenarios and skips change-detection; leave it empty to fall back to
change-detection. The same variable can be supplied via the ITS
`PIPELINE_TEST_SUITE_VARS` (it is `PTSV_`-prefixed).

Only the components used by the **enabled** scenarios are built each run:
`select_components_for_matrix()` in `test.sh` narrows `PTSV_COMPONENTS` to that
set (via the `SCENARIO_COMPONENTS` map), and `filter_tenant_kustomization()`
drops the other components' files from the tenant kustomization before it is
applied. So, e.g., with only the single scenarios enabled, `component2` is not
built and `component` is alone in the default application (which guarantees a
clean single-component snapshot for `single-staged`/`prega`/`hotfix`).

The full component set is listed in `resources/tenant/kustomization.yaml`.
Which component each scenario uses:

| Scenario | Application | Component(s) |
|----------|-------------|--------------|
| `single-staged`, `single-prega`, `single-hotfix` | default | `component` |
| `single-happy` | isolated (happy) | `happy-component` |
| `multi-staged` | default | `component` + `component2` |
| `multi-happy` | isolated (multi-happy) | `multi-happy-component-1` + `multi-happy-component-2` |
| `single-optin` | optin | `optin-component` |
| `multi-optin` | multi-optin | `multi-optin-component-1` + `multi-optin-component-2` |

*opt-in components have the `fbc-opt-in` flag set to true in pyxis.*

### Why the components are separated

`update-fbc-catalog` reuses a prior IIB build when it finds a completed (or
in-progress) build with the same `(from_index, fbc_fragments)` reuse key.
Scenarios that share a Snapshot therefore share that key and can reuse each
other's builds.

- That reuse is **correct** for the non-overwrite scenarios
  (`staged`/`prega`/`hotfix`): they issue the identical "add fragments to
  from_index" IIB operation, so sharing a build is fine (and saves work).
- It is **wrong** for the GA "happy" scenarios: they set
  `overwrite_from_index=true`, and reusing a non-overwrite build makes
  `update-fbc-catalog` fail `validate_index_image` (`index_image != from_index`).

So each isolated scenario gets its own **Snapshot** (own component + application)
— a distinct `fbc_fragments`, hence a distinct reuse key — so builds are never
reused across scenarios. OCP versions are randomized (`shuf`) to spread scenarios
across `from_index` values and to avoid reusing builds from previous CI runs.

> **Limitation (all-in-one run):** the OCP pool is smaller than the number of
> scenarios, so in a single run **not every overwrite scenario gets a unique
> `from_index`** — e.g. `single-happy` currently shares
> `iib-preview-rhtap:<OCP>` with the non-overwrite single scenarios, and
> `single-optin`/`multi-optin-1` share one too. Cross-scenario *build* reuse is
> still prevented (distinct fragments → distinct reuse key), but an overwrite
> release can touch a `from_index` another scenario is reading. Full per-scenario
> `from_index` isolation comes with the **per-scenario split** (running each
> scenario as its own integration test / run), which is the planned direction.

The multi scenarios build their two components at **different OCP versions**, so
each snapshot spans two OCP groups and exercises `add-fbc-contribution`'s
**per-OCP split** (one IIB request per OCP group). The two components still use
different packages (`example-operator`, `example-operator2`) — a carry-over from
the earlier same-OCP batching layout; with different OCPs it's no longer required
for correctness.

> **Coverage note:** no non-opt-in multi scenario currently exercises **same-OCP
> batching** (multiple fragments in a single IIB request). To add that coverage,
> pin a multi pair to one shared OCP version — and keep the two distinct packages
> so the batched request has no duplicate-package conflict.

### Where the directory structure comes from

Each component's git repo is created per test run by copying a base branch (see
`<comp>_base_repo_name` / `<comp>_base_branch` in `test.env`, driven by
`PTSV_COMPONENTS` via `scripts/copy-branch-to-repo-git.sh`). The base branch's
on-disk layout is exactly what each component's `context` points into:

- **`hacbs-release-tests/e2e-base` @ `fbc-release-multi-base`** — the non-opt-in
  components. Component-first layout, for `v4.13`..`v4.20`:
  - `component/v<OCP>/{catalog.Dockerfile, catalog/example-operator/}`
  - `component2/v<OCP>/{catalog.Dockerfile, catalog/example-operator2/}`

  `context: <dir>/v<OCP>` + `dockerfileUrl: catalog.Dockerfile` selects the
  operator package and the OCP version.
- **`hacbs-release-tests/e2e-operator-fbc` @ `main`** — the opt-in components.
  Version dirs (`v<OCP>/`) sit at the repo root (no `component/` prefix), so
  their context is just `v<OCP>`.
