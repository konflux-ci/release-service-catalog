# create-pyxis-image

Tekton task that pushes metadata to Pyxis for all container images contained in a snapshot that is the
result of the `apply-mapping` task. It first extracts the containerImages from the snapshot, then runs
`skopeo inspect` on each, before finally pushing metadata to Pyxis.

The relative path of the pyxis.json file in the data workspace is output as a task result named
`pyxisDataPath`.

## Parameters

| Name        | Description                                                                                        | Optional | Default value |
|-------------|----------------------------------------------------------------------------------------------------|----------|---------------|
| server      | The server type to use. Options are 'production' and 'stage'                                       | Yes      | production    |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert  | No       | -             |
| certified   | If set to true, the images will be marked as certified in their Pyxis entries                      | Yes      | false         |
| isLatest    | If set to true, the images will have a latest tag added with their Pyxis entries                   | Yes      | false         |
| rhPush      | If set to true, an additional entry will be created in ContainerImage.repositories with the registry and repository fields converted to use Red Hat's official registry. E.g. a mapped repository of "quay.io/redhat-pending/product---my-image" will be converted to use registry "registry.access.redhat.com" and repository "product/my-image". Also, this repository entry will be marked as published.                                                                                                         | Yes      | false         |
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace                         | No       | -             |

## Changes in 3.2.0
* Updated the base image used in this task

## Changes in 3.1.0
* added support for OCI artifacts.

## Changes in 3.0.0
* `dataPath` and `commonTags` parameters removed
  * These were only used for determining the tags to create the pyxis image with. These now come from the individual
    component entries in the snapshot spec file

## Changes in 2.8.0
* Updated the base image used in this task

## Changes in 2.7.1
* Only run the cleanup_tags script to clean up tags from previous images if rhPush=true
  * The script expects to find a registry.access.redhat.com repository entry for the image
    (which is only created if rhPush=true), so it would fail for images that do not have one.
* Use set -e for the step script. Without it, the script would carry on even if something failed along the way,
  e.g. if the cleanup_tags script failed because of Pyxis issues, we would still continue onto the next
  iteration in the loop. We should fail the task in this case.

## Changes in 2.7.0
* Updated the base image used in this task

## Changes in 2.6.1
* For each image that is created in Pyxis, the task will now also remove
  all its tags from all previous images
  * This is done via a new script called cleanup_tags from the utils image

## Changes in 2.6.0
* containerImage is no longer saved in the pyxis.json entries
  * This was already saved in pyxis.json per component, it doesn't need to be duplicated in the pyxisImages keys
* os is now saved to the pyxis.json pyxisImages entries

## Changes in 2.5.0
* The task now looks for tags in each component of the snapshot spec file and uses them instead of commonTags if any
  exist

## Changes in 2.4.0
* containerImageIDs result is removed as the data is present in pyxis.json that is written to the workspace
* the containerImage is now saved in the pyxis.json entries
* the pyxis.json file is saved in the same subdirectory as the passed snapshot file

## Changes in 2.3.0
* remove `dataPath` and `snapshotPath` default values

## Changes in 2.2.2
* Support populating multiarch image entities correctly

## Changes in 2.2.1
* Add support for server types of production-internal and stage-internal

## Changes in 2.2.0
* Add feature of pushing multi architecture images metadata to Pyxis

## Changes in 2.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 1.2.0
* Create a floating tag when tagPrefix is set
  * This is in addition to the tag tagPrefix-timestamp a.k.a. commonTag that we create in Pyxis now
* Update image used in the task
  * The new image supports multiple tags in the create_pyxis_image Python script

## Changes in 1.1.2
* Update image used in the task
  * When rhPush is true, now we'll create two entries in ContainerImage.repositories - one is the normal one and the other
    is the special one with registry="registry.access.redhat.com"

## Changes in 1.1.1
* Use the image digest when doing skopeo inspect
  * Without a digest, the `latest` tag was assumed. But if it was missing, the command would fail

## Changes in 1.1.0
* Update image used in the task
  * The new image contains fix for missing image_id field when creating the Pyxis Container Image object

## Changes in 1.0.0
* Add optional `rhPush` parameter
  * This will be used in the `rh-push-to-registry-redhat-io` to use the proper `registry` and `repository` values when
    creating the Container Image object in Pyxis. Also, the image will be marked as published.
* Add optional `commonTag` parameter
  * If set, the `tag` in the Pyxis Container Image object will be set to it

## Changes in 0.5
* The tag parameter is removed
  * The default tag is now provided by the 'images.defaultTag' key in the data JSON file as the pipeline parameter will
    no longer be passed.
  * dataPath parameter to point to the data JSON file in the data workspace was added.

## Changes in 0.4
* Update Tekton API to v1

## Changes in 0.3
* mappedSnapshot parameter was removed and snapshotPath parameter was added
  * Instead of passing a json string representing the snapshot, the snapshot spec should exist in the data workspace
    in the filename provided by snapshotPath.

## Changes in 0.2
* Use tag present in mapping file if present.
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes in 0.1
* Fix for incorrect snapshot param.
