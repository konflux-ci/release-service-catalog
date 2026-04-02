# filter-published-fbc-images

Tekton task that filters already-published FBC fragments from a Snapshot before release.

## Description

Before triggering an IIB build, this task compares every FBC fragment in the Snapshot against
previously successful Release CRs for the same application. Any fragment whose digest matches a
`status.artifacts.components[].fbc_fragment` value from a completed Release targeting the same
`target_index` is removed from the filtered snapshot. This prevents redundant IIB builds on
re-releases.

The task also attaches an `ocpVersion` field to every component that passes through, derived from
the `org.opencontainers.image.base.name` OCI annotation on the fragment image. This field is
required by downstream tasks.

**Safe fallback**: if `releaseName` is omitted, the Release CR lookup fails, or the Kubernetes API
is unavailable, all components are kept and the task succeeds (the actual release tasks will
handle any errors downstream).

## Parameters

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| snapshotPath | string | Yes | - | Path to the JSON snapshot spec in the data workspace |
| dataPath | string | Yes | - | Path to the merged data JSON in the data workspace |
| releaseName | string | No | `""` | Namespaced name (`namespace/name`) of the current Release CR. Used to discover previously completed Releases for the same application. If empty, filtering is skipped. |
| ociStorage | string | No | `"empty"` | OCI repository for Trusted Artifacts storage |
| ociArtifactExpiresAfter | string | No | `"1d"` | Expiration for trusted artifacts |
| trustedArtifactsDebug | string | No | `""` | Enable debug logging in trusted artifacts |
| orasOptions | string | No | `""` | Extra options passed to oras in trusted artifact calls |
| sourceDataArtifact | string | No | `""` | Location of trusted artifacts to populate the data directory |
| dataDir | string | No | `/var/workdir/release` | Root directory for data files |
| taskGitUrl | string | Yes | - | Git repository URL for release-service-catalog tasks |
| taskGitRevision | string | Yes | - | Revision in taskGitUrl to use |

## Results

| Name | Description |
|------|-------------|
| filteredSnapshotPath | Path to the filtered snapshot (with `ocpVersion` attached). Consumed by EC validation and downstream tasks. |
| sourceDataArtifact | Trusted artifact produced by this task |
