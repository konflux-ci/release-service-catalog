# FBC Idempotency — Coverage Gaps

This document lists **what is not yet tested** for `filter-published-fbc-images` and
the `fbc-release` pipeline, organized by failure category.

Implemented unit tests (14) and existing E2E tests (`fbc-release-idempotent`, TC-01,
TC-02) are not listed here — see
[`tasks/managed/filter-published-fbc-images/tests/`](tasks/managed/filter-published-fbc-images/tests/)
and [`integration-tests/fbc-release-idempotent/`](integration-tests/fbc-release-idempotent/).

---

## Unit Test Gaps (implementable now)

### Fragmented / Release CR data edge cases

#### `test-filter-published-fbc-no-app-label` — missing application label
**Branch not covered**: `kubectl get release <name>` returns an empty application label
(the Release CR exists but lacks the `appstudio.openshift.io/application` label).
The task falls back to keeping all components (line 320–327 in the script). No test
currently exercises this path — the existing `kubectl-rbac-failure` test only covers
the `kubectl list` call failing, not the earlier `kubectl get` call returning empty.

**Mock route**: `current-release-no-app-label` → `get release <name>` returns `""`.

**Expected**: all components kept, ocpVersion attached.

---

#### `test-filter-published-fbc-release-no-artifacts` — completed Release with no artifacts
**Branch not covered**: a prior Release has `Released=True` in its conditions but
`status.artifacts` is `null` or absent entirely. The jq expression
`(.status.artifacts.components // [])[]` should safely yield zero digests, keeping
all current-snapshot components. Currently untested — the `release-not-completed`
test exercises `Released=False`; no test exercises the `Released=True` + no-artifacts case.

**Mock route**: new `test-app-no-artifacts` entry returning a Release item with
`"conditions": [{"type": "Released", "status": "True"}]` and no `artifacts` field.

**Expected**: all components kept (no digests to compare against).

---

### Multi-release accumulation (partial + history)

#### `test-filter-published-fbc-multi-release-history` — union across several prior releases
**Branch not covered**: the jq query iterates over ALL `.items[]` from all prior
successful Releases, taking the union of digests. Currently every test that exercises
filtering has exactly one prior Release CR. This means the union path is never actually
exercised — if the union logic had a bug (e.g. only the last Release's fragments were
used) no existing test would catch it.

**Scenario**: two prior Release CRs, both `Released=True`, both targeting the same
index:
- Release A: recorded `sha256:F1`
- Release B: recorded `sha256:F3`

New snapshot: `comp1@sha256:F1`, `comp2@sha256:F2`, `comp3@sha256:F3`, `comp4@sha256:F4`.

Expected filtered snapshot: only `comp2` and `comp4` (F1 from A and F3 from B both
filtered; F2 and F4 not in any Release CR).

**Mock route**: new `test-app-history` entry returning two Release items for the same
target index.

---

### Multi-version + partial combined

#### `test-filter-published-fbc-multi-ocp-partial` — per-index partial filtering across two OCP versions
**Branch not covered**: the combination of multi-OCP grouping AND partial filtering
within each group. Existing tests cover them separately: `multi-ocp-versions` tests
per-index grouping (one published per index), `partial-published` tests partial
filtering for a single index. No test combines both axes.

**Scenario**: four components, two OCP versions, each version partially published:
- `comp1@sha256:P1`, OCP v4.14 → in prior Release CR for v4.14 index → **filter out**
- `comp2@sha256:N2`, OCP v4.14 → NOT in any Release CR → **keep**
- `comp3@sha256:N3`, OCP v4.16 → NOT in any Release CR → **keep**
- `comp4@sha256:N4`, OCP v4.16 → NOT in any Release CR → **keep**

Expected: filtered snapshot has `comp2`, `comp3`, `comp4`; `comp1` is removed.

**Mock route**: new `test-app-multi-partial` returning one prior Release with `sha256:P1`
only for the v4.14 target index, and empty artifacts for the v4.16 index.

---

## E2E Integration Gaps

### All-published (empty filtered snapshot) — TC-07: full pipeline pass

**Status: ✅ Implemented**

`prepare-fbc-snapshot` and `prepare-fbc-parameters` now handle an empty filtered
snapshot gracefully:
- `prepare-fbc-snapshot`: exits 0, logs that nothing needs to be prepared. The snapshot
  file is unchanged so the trusted artifact step produces a valid (empty) artifact.
- `prepare-fbc-parameters`: writes `mustPublishIndexImage=false`, `mustSignIndexImage=false`,
  and `mustOverwriteFromIndexImage=false`, then exits 0. Downstream tasks skip via their
  existing `when` conditions on `mustPublishIndexImage`.

Phase 3 in `fbc-release-idempotent` (`wait_for_release` hard wait, `expected_skipped="true"`)
now exercises the full path end-to-end: filter finds all fragments → empty snapshot → both
prepare tasks exit 0 → `add-fbc-contribution` skipped → pipeline succeeds.

Unit tests:
- `tasks/managed/prepare-fbc-snapshot/tests/test-prepare-fbc-snapshot-empty-snapshot.yaml`
- `tasks/managed/prepare-fbc-parameters/tests/test-prepare-fbc-parameters-empty-snapshot.yaml`

---

### Partial — TC-03: some fragments published, some new

**Status: ✅ Implemented**

`run_tc03_partial_filtering` in `fbc-release-idempotent/test.sh` implements this:
1. After Phase 1 (multi-OCP, two components), extract comp2's `fbc_fragment` and
   `target_index` from Phase 1's Release CR.
2. Create a fixture Release CR patched with `Released=True` recording only comp2.
3. Release the multi-component snapshot (comp1 + comp2) against the fixture.
4. Assert: `add-fbc-contribution` ran (comp1 was kept); filter logs show comp2 FILTERED,
   comp1 KEPT.

TC-03 is skipped automatically if Phase 1 did not complete with both components
(e.g., IIB failure for v4.14 in staging).

---

### Multi-release accumulation — TC-06: union across three sequential releases

**What it tests**: Release 1 publishes `comp1`. Release 2 publishes `comp2`. Release 3
triggers with a snapshot containing `comp1 + comp2 + comp3`. The filter must consult
both prior Release CRs, accumulate their fragments, and pass only `comp3` to
`add-fbc-contribution`.

This is the most realistic production scenario for an iterative operator catalog — each
release adds one or two new FBC packages to an index that already contains many from
prior runs.

**Why unit tests are not enough**: the accumulation path in the real pipeline also
depends on the Release controller writing the correct `status.artifacts.components[]`
structure. A bug there (e.g. empty `fbc_fragment` field) would evade unit test mocks.

**Complexity**: Medium-High. Requires three sequential releases and assertions after each.

---

### All-published (empty filtered snapshot) — TC-07: pipeline handles zero components

**What it tests**: a second release of an IDENTICAL snapshot after the first succeeded.
The filter produces a snapshot with ZERO components. This is a critical path because:

- Downstream tasks (`add-fbc-contribution`, `sign-index-image`) receive an empty
  component list and must handle it gracefully without crashing.
- The Release CR `status.artifacts` must reflect zero new contributions.
- No new IIB build should be triggered.

Currently this scenario is covered at unit level (`all-published` test) but never
run end-to-end. A downstream task that assumes `components` is non-empty would
silently break here.

**Complexity**: Low — trigger the existing `fbc-release-idempotent` test with a
completed Phase 1 Release CR already in place, skip straight to Phase 2, and assert
that the pipeline completes without calling `add-fbc-contribution`.

---

### Race condition — TC-02 deterministic variant

The existing TC-02 implementation is timing-based: Phase 2 is started concurrently
with Phase 1 hoping the filter task fires before Phase 1 completes. This is
non-deterministic and prints a warning rather than failing if timing doesn't hold.

**Deterministic alternative**: pre-create a Release CR for the same application with
`status.conditions = [{type: Released, status: Unknown, reason: Running}]` (in-flight,
not completed). Then trigger a release and verify:

1. The filter task sees this in-flight Release but correctly ignores it (not `True`).
2. All components are kept.

This removes the timing dependency while still exercising the in-flight-release path.

**Complexity**: Low — replace the concurrent trigger with a pre-seeded fixture CR.

---

### Partial delivery — TC-05: Release CR incomplete after mid-pipeline failure

**What it tests**: Phase 1's pipeline fails after `add-fbc-contribution` completes
(IIB index image built) but before `create-advisory` finishes. The Release CR's
`Released` condition is `False` (or never set to `True`).

Phase 2 must re-run the full pipeline because the prior Release was not completed:

1. `filter-published-fbc-images` sees the prior Release with `Released=False` → not
   counted → all components kept.
2. `add-fbc-contribution` runs again.
3. The release completes.

The unit test `test-filter-published-fbc-release-not-completed` covers the filter
decision. The E2E scenario requires injecting a pipeline failure mid-way.

**Complexity**: High — requires chaos injection or a pipeline that intentionally fails
at a specific task.

---

## Summary

| Gap | Type | Complexity | Status |
|---|:---:|:---:|---|
| `no-app-label` unit test | unit | Low | ✅ implemented |
| `release-no-artifacts` unit test | unit | Low | ✅ implemented |
| `multi-release-history` unit test | unit | Low | ✅ implemented |
| `multi-ocp-partial` unit test | unit | Low | ✅ implemented |
| TC-00/TC-01/TC-02 e2e (Pyxis → Release CR migration) | e2e | Medium | ✅ implemented |
| TC-07 E2E (all-published, empty snapshot) | e2e | Low | ✅ implemented — pipeline gap fixed in `prepare-fbc-snapshot` and `prepare-fbc-parameters` |
| TC-03 E2E (partial new) | e2e | Medium | ✅ implemented — fixture Release CR via `kubectl patch --subresource=status` |
| TC-06 E2E (3-release accumulation) | e2e | Medium-High | pending — most realistic production scenario |
| TC-02 deterministic race condition | e2e | Low | pending — replace timing-based with fixture in-flight CR |
| TC-05 E2E (partial delivery) | e2e | High | pending — requires chaos injection |

---

## Related

- [`tasks/managed/filter-published-fbc-images/`](tasks/managed/filter-published-fbc-images/) — task under test
- [`integration-tests/fbc-release-idempotent/`](integration-tests/fbc-release-idempotent/) — idempotency test suite
- [RELEASE-2379](https://redhat.atlassian.net/browse/RELEASE-2379) — root bug
