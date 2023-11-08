# apply-mapping

Tekton task to apply a mapping to an Snapshot.

The purpose of this task is to merge a mapping with the components contained in an Snapshot.
The mapping is expected to be present in the data field of the ReleasePlanAdmission provided in
the `releasePlanAdmissionPath`. If the data field does not contain a `mapping` key, the original
Snapshot is returned. If there is a `mapping` key, it is merged with the `components` key in the
Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Snapshot is being returned or the original one.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshotPath | Path to the JSON string of the Snapshot spec in the config workspace to apply the mapping to | Yes | snapshot_spec.json |
| releasePlanAdmissionPath | Path to the JSON string of the ReleasePlanAdmission in the config workspace which contains the mapping to apply | Yes | release_plan_admission.json |
| failOnEmptyResult | Fail the task if the resulting snapshot contains zero components | Yes | false |

## Changes since 0.8.0
  * Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 0.7.0
  * No longer uses extraConfigPath
    * The mapping is provided by the ReleasePlanAdmission now instead. This change includes replacing the `extraConfigPath`
      parameter with the `releasePlanAdmissionPath` parameter

## Changes since 0.6
  * Update Tekton API to v1

## Changes since 0.5
  * Instead of saving the mapped json to a new file, override the original snapshot spec file
    * We never really use the original after the mapping anyway and this way we can continue to use the path to the snapshot
      that we already know in other tasks of the pipeline (at the moment the mapped json file is hardcoded in other places
      of the pipeline that use it).

## Changes since 0.4
  * The snapshot parameter was replaced with the snapshotPath parameter
    * The snapshot is now provided via the workspace instead of directly as a parameter
    * The mapped snapshot is now stored in a `mapped_snapshot.json` file in the workspace instead of as a task result

## Changes since 0.3

  * New optional parameter `failOnEmptyResult` was added. When enabled, the task
    will fail if the resulting snapshot contains 0 components.

## Changes since 0.2

  * Base image was changed from `release-utils` to `release-base-image`
  * The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes since 0.1 (milestone-8)

  * Task `apply-mapping` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
