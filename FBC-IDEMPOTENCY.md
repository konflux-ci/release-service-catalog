# FBC Release Idempotency — Solution Design

This document explains the problem that motivated the `filter-published-fbc-images`
redesign, why the original approach was fundamentally broken, what was changed, and
how the current solution works.

---

## Background

The Konflux FBC (File-Based Catalog) release pipeline publishes OLM operator catalog
fragments to Red Hat's index images using IIB (Index Image Builder). A "fragment" is
a container image that carries a partial OLM catalog tree — a set of operator package
definitions that get merged into a versioned index image (e.g. the v4.14 or v4.16
OpenShift catalog).

When a release pipeline runs for a snapshot that was already successfully released,
re-running the pipeline without any guard would:

- Submit redundant IIB build requests for fragments that are already in the index.
- Re-sign index images that have not changed.
- Potentially create duplicate advisory entries.
- Consume unnecessary compute and pipeline quota.

The `filter-published-fbc-images` task is the guard. It sits at the start of the
pipeline and removes from the snapshot any FBC fragments that are already present
in the published index, so that downstream tasks only process what is genuinely new.

---

## Why the Original Approach Failed

### What it did

The original implementation queried Red Hat's **Pyxis** image metadata service.
For each unique target index in the snapshot (one per OCP version), it issued an
HTTP request to the Pyxis `/v1/images` endpoint, filtering by the registry, repository,
and tag of the index image. The expectation was that Pyxis would return a
`ContainerImage` record that included the digests of the FBC fragment images that
had been contributed to that index.

### The fundamental data gap

The assumption was incorrect. The Pyxis `ContainerImage` schema stores metadata
about an index image as a whole — its digest, registry location, labels — but it does
**not** store which FBC fragment images were merged into it. The `related_images`
and `bundles` fields in the Pyxis schema are OLM concepts tied to the traditional
operator-certification pipeline (CSV-based bundles). They are not populated by the
FBC contribution workflow.

In practice:

- Pyxis would return an HTTP 200 response with a valid `ContainerImage` record.
- The record would contain no `related_images` or `bundles` fields.
- Fragment digest extraction would yield an empty list.
- The filter would conclude "no published fragments" and keep all components.
- Every re-release would run the full IIB build regardless of whether the fragments
  were already present.

The filter appeared to work (it never crashed), but it was not performing any actual
filtering. Idempotency was effectively disabled.

### The query bug (separate from the data gap)

In addition to the data gap, the original implementation also contained a query bug:
it filtered Pyxis records by `docker_image_id`, which stores a config-layer digest
rather than an image location. Pyxis records are indexed by registry + repository +
tag, so queries by `docker_image_id` returned empty results even when the index image
was present in Pyxis. This was discovered during investigation of
[RELEASE-2379](https://redhat.atlassian.net/browse/RELEASE-2379) and was fixed
(using `repositories.registry`, `repositories.repository`, `repositories.tags.name`),
but correcting the query only revealed the deeper schema gap: even with the right
query, Pyxis does not carry fragment-level data.

### Why it "worked" in staging

The Pyxis staging environment (`pyxis.stage.engineering.redhat.com`) had even less
data than production. Preview index images built by IIB in staging were largely absent
from the staging Pyxis instance, so the filter always returned empty results and kept
all components — which matched expected staging behavior (always release). The
absence of data masked the fundamental limitation.

---

## What Was Changed

The implementation was redesigned to use **Kubernetes Release CRs** as the source of
truth for previously published FBC fragments, completely replacing the Pyxis HTTP
calls.

The following changes were made across the codebase:

**`tasks/managed/filter-published-fbc-images/filter-published-fbc-images.yaml`**
— Core task script rewritten. The Pyxis HTTP query logic, certificate handling, and
`setup-pyxis-cert` step were removed. A new `releaseName` parameter was added (the
namespaced name of the current Release CR). The filtering logic now queries the
Kubernetes API for Release CRs in the tenant namespace instead of calling Pyxis.

**`pipelines/managed/fbc-release/fbc-release.yaml`**
— The `filter-published-fbc-images` task call was updated to remove `pyxisSecret`
and pass `$(params.release)` as the new `releaseName` parameter.

**`tasks/managed/filter-published-fbc-images/tests/mocks.sh`**
— Test mocks were completely rewritten. The `curl` Pyxis mock was replaced with a
`kubectl` Release CR mock. Eighteen unit tests were updated or rewritten to use
the new parameter and mock approach.

---

## How the Current Solution Works

### Data source: Release Custom Resources

Every release managed by the Konflux Release Service creates a **Release CR** in the
tenant namespace. When a release pipeline completes successfully, the Release controller
writes the delivered artifacts into the Release CR's status:

- `status.conditions[]` — includes a condition with `type: Released` and `status: True`
  when the release fully succeeded.
- `status.artifacts.components[].fbc_fragment` — the exact pullspec (including digest)
  of the FBC fragment image that was contributed.
- `status.artifacts.components[].target_index` — the index image the fragment was
  contributed to (e.g. `quay.io/redhat/redhat----preview-operator-index:v4.14`).

This data is written by the same `fbc-release` pipeline that the filter task is part
of. It is authoritative: if the Release controller wrote `fbc_fragment = sha256:X`
for a given target index, that fragment was genuinely delivered.

### Step-by-step execution

**1. OCP version extraction**

For every component in the snapshot, the task inspects the fragment image using
`skopeo inspect` and reads the `org.opencontainers.image.base.name` OCI annotation,
which carries the base image reference including the OCP version tag (e.g. `v4.14`).
This determines which index image the fragment targets. All OCP versions are validated
and extracted before any filtering begins.

**2. Target index resolution**

The `fbc.targetIndex` field in the pipeline's data file may be a literal index image
reference or a template containing `{{ OCP_VERSION }}`. The task substitutes the
extracted OCP version for each component, producing one resolved target index per
component. Components that resolve to the same target index are grouped together.

**3. Application name lookup**

The task reads the `releaseName` parameter (format: `namespace/name`), then queries
the current Release CR to retrieve the `appstudio.openshift.io/application` label.
This label is the application name that links all historical releases for the same
product together.

**4. Release CR query per target index**

For each unique target index, the task lists all Release CRs in the tenant namespace
that carry the same application label. From this list it extracts the fragment digest
for every component whose `target_index` matches the current one, but only from
releases that:

- Are not the current in-flight release (excluded by name).
- Have `status.conditions` with `type: Released` and `status: True` (completed
  successfully).

This produces a set of previously-published fragment digests for each target index.
Fragments from failed or incomplete releases are excluded, which correctly handles
partial-delivery scenarios where a prior pipeline crashed mid-run.

**5. Filtering decision**

For each snapshot component, the task extracts the digest from its `containerImage`
reference and checks whether that digest appears in the published-fragments set for
the component's resolved target index. If it does, the component is removed from the
filtered snapshot. If it does not, the component is kept.

**6. Output**

The task writes a `filtered-snapshot.json` containing only the components that are
new (not previously released), with the `ocpVersion` field attached to each. This
file is consumed by all downstream tasks in the pipeline.

### Safe fallbacks

The task is designed to fail open: if it cannot determine what was previously released,
it keeps all components rather than blocking the release. Specific safe-fallback
conditions are:

- `releaseName` parameter is empty — no lookup is performed; all components kept.
- The current Release CR has no application label — cannot group releases; all kept.
- The `kubectl list` call fails (RBAC denial, API unavailability) — all components kept.
- The kubectl response is malformed JSON — all components kept.
- A prior Release has `Released=True` but no `status.artifacts` field — that release
  contributes zero digests to the filter set (not a failure; treated as "nothing
  published in that release").
- `stagedIndex=true` in the pipeline data — staged builds are always treated as
  first-release; filtering is skipped entirely.

In all fallback cases the task exits with status zero and the pipeline continues
normally. A log warning is written so the reason is visible in the pipeline run output.

### RBAC requirement

The task runs with the service account used by the managed pipeline run. That
service account must have `list` permission on `Release` resources in the tenant
namespace. In standard Konflux deployments this permission is expected to exist
because the Release controller and pipeline share cross-namespace access patterns for
the same application.

---

## Properties of the Solution

**Correctness** — The Release CR `status.artifacts` field is written by the same
delivery pipeline after a verified successful delivery. It is the most authoritative
available record of "what was actually released."

**Partial delivery safety** — A Release with `Released=False` is explicitly excluded
from the published-fragments set. If a prior run delivered an IIB build but failed
before completing the advisory or signing steps, the next run will re-do the full
pipeline rather than incorrectly treating the fragment as published.

**Historical accumulation** — The query covers all prior Releases for the application,
not just the most recent one. Fragments published in Release A and fragments published
in Release B are both accumulated and excluded from a third release. This supports
real-world incremental catalog growth where each release adds a few new packages to an
index that already contains many from earlier runs.

**Per-index granularity** — Each unique target index is queried independently. A
fragment targeting v4.14 is never confused with one targeting v4.16, even if the same
snapshot contains components for both.

**Kubernetes-native** — No external service dependency. The data lives in the same
cluster and namespace as the pipeline run itself. This eliminates the certificate
management, HTTP retry logic, and external network reachability constraints that the
Pyxis approach required.

---

## Remaining Limitations

**First-party data only** — The filter can only consult releases managed through
Konflux. If a fragment was published via a different mechanism (manual IIB submission,
a legacy pipeline), it will not be recorded in any Release CR and will not be filtered
out.

**No cross-application scope** — The filter looks up releases by application label.
If an operator's fragments are published under different application names in different
releases, the historical record is fragmented and the filter may not find all prior
releases.

**No downstream completion check** — The filter uses the top-level `Released=True`
condition as a proxy for "fully delivered." It does not inspect whether every
downstream delivery channel (advisory, signing, Pyxis registration) individually
succeeded. A future enhancement could add a more granular completion check against
per-task status fields in the Release CR.

For open E2E test gaps and planned improvements, see [TEST-COVERAGE.md](TEST-COVERAGE.md).

---

## Related

- [RELEASE-2379](https://redhat.atlassian.net/browse/RELEASE-2379) — root bug
- [`tasks/managed/filter-published-fbc-images/`](tasks/managed/filter-published-fbc-images/) — task source
- [`tasks/managed/filter-published-fbc-images/README.md`](tasks/managed/filter-published-fbc-images/README.md) — parameter reference
- [`pipelines/managed/fbc-release/fbc-release.yaml`](pipelines/managed/fbc-release/fbc-release.yaml) — pipeline
- [`TEST-COVERAGE.md`](TEST-COVERAGE.md) — open test gaps
