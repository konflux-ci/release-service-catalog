# apply-mapping

Tekton task to apply a mapping to an Snapshot.

The purpose of this task is to merge a mapping with the components contained in an Snapshot.
The mapping is expected to be present in the passed `extraConfigPath`. If the file is not found or
the file contains no `mapping` key, the original Snapshot is returned. If there is a
`mapping` key, it is merged with the `components` key in the Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Snapshot is being returned or the original one.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| snapshot | The Snapshot in JSON format to apply the mapping to | No | - |
| extraConfigPath | The path to the config file containing the mapping | Yes | - |
| failOnEmptyResult | Fail the task if the resulting snapshot contains zero components | Yes | false |

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
