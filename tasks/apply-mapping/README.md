# apply-mapping

Tekton task to apply a mapping to an Snapshot.

The purpose of this task is to merge a mapping with the components contained in an Snapshot.
The mapping is expected to be present in the data field of the ReleasePlanAdmission provided in
the `releasePlanAdmissionPath`. If the data field does not contain a `mapping` key, the original
Snapshot is returned. If there is a `mapping` key, it is merged with the `components` key in the
Snapshot based on component name.

A `mapped` result is also returned from this task containing a simple true/false value that is
meant to inform whether a mapped Snapshot is being returned or the original one.

This task supports variable expansion in tag values from the mapping. The currently supported variables are:
* "{{ timestamp }}" -> The current time in the format provided by timestampFormat or %s as the default
* "{{ git_sha }}" -> The git sha that triggered the snapshot being processed
* "{{ git_short_sha }}" -> The git sha reduced to 7 characters
* "{{ digest_sha }}" -> The image digest of the respective component

## Parameters

| Name              | Description                                                                                  | Optional | Default value |
|-------------------|----------------------------------------------------------------------------------------------|----------|---------------|
| snapshotPath      | Path to the JSON string of the Snapshot spec in the config workspace to apply the mapping to | No       | -             |  
| dataPath          | Path to the JSON string of the merged data to use in the data workspace                      | No       | -             |
| failOnEmptyResult | Fail the task if the resulting snapshot contains zero components                             | Yes      | false         |

## Changes in 1.4.0
* Add a check that all component containerImage values use a sha reference
  * If some value does not comply, fail the task

## Changes in 1.3.1
* Fix bug when there are no tags
  * Without a default `[]` value when loading tags for components with jq, the tags variable
    would be an empty string instead of an empty array, which would result in an error
    running `jq 'length'` on it

## Changes in 1.3.0
*  Updated the base image used in the task

## Changes in 1.2.0
 * Variable expansion is now done in each component's staged.files.filename values too

## Changes in 1.1.0
 * Updated the base image used in this task

## Changes in 1.0.0
 * Use the data json instead of the ReleasePlanAdmission json
    * releasePlanAdmissionPath parameter removed in favor of dataPath parameter

## Changes in 0.11.0
 * The tags provided in `mapping.defaults.tags` are combined with each components `.tags` entry to form
   one set of tags
   * The resulting tags are stored in the snapshot spec file under each component
   * The supported variables will be replaced in the tags

## Changes in 0.10.0
 * Removed default values for `snapshotPath` and `releasePlanAdmissionPath`

## Changes in 0.9.1
  * Replaced `echo` with `printf` for storing results.
    Using `echo` resulted in appending `true\n` to the output,
    which caused discrepancies with the `when` expression in the pipeline.

## Changes in 0.8.0
  * Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.7.0
  * No longer uses extraConfigPath
    * The mapping is provided by the ReleasePlanAdmission now instead. This change includes replacing the `extraConfigPath`
      parameter with the `releasePlanAdmissionPath` parameter

## Changes in 0.6
  * Update Tekton API to v1

## Changes in 0.5
  * Instead of saving the mapped json to a new file, override the original snapshot spec file
    * We never really use the original after the mapping anyway and this way we can continue to use the path to the snapshot
      that we already know in other tasks of the pipeline (at the moment the mapped json file is hardcoded in other places
      of the pipeline that use it).

## Changes in 0.4
  * The snapshot parameter was replaced with the snapshotPath parameter
    * The snapshot is now provided via the workspace instead of directly as a parameter
    * The mapped snapshot is now stored in a `mapped_snapshot.json` file in the workspace instead of as a task result

## Changes in 0.3

  * New optional parameter `failOnEmptyResult` was added. When enabled, the task
    will fail if the resulting snapshot contains 0 components.

## Changes in 0.2

  * Base image was changed from `release-utils` to `release-base-image`
  * The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes in 0.1 (milestone-8)

  * Task `apply-mapping` was changed
    * Task parameter `applicationSnapshot` value was changed
      * old: $(params.applicationSnapshot)
      * new: $(params.snapshot)
