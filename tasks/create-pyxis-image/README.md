# create-pyxis-image

Tekton task that pushes metadata to Pyxis for all container images contained in a snapshot that is the
result of the `apply-mapping` task. It first extracts the containerImages from the snapshot, then runs
`skopeo inspect` on each, before finally pushing metadata to Pyxis.

The IDs of the created `containerImage` Pyxis objects are stored as a task result with each ID separated
by a new line.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| server | The server type to use. Options are 'production' and 'stage' | Yes | production |
| pyxisSecret | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No | - |
| certified | If set to true, the images will be marked as certified in their Pyxis entries | Yes | false |
| isLatest | If set to true, the images will have a latest tag added with their Pyxis entries | Yes | false |
| rhPush | If set to true, an additional entry will be created in ContainerImage.repositories with the registry and repository fields converted to use Red Hat's official registry. E.g. a mapped repository of "quay.io/redhat-pending/product---my-image" will be converted to use registry "registry.access.redhat.com" and repository "product/my-image". Also, this repository entry will be marked as published. | Yes | false |
| commonTags | Space separated list of common tags to be used when publishing. If set, these tags will be added to the Pyxis Container Image object. | Yes | "" |
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace | Yes | mapped_snapshot.json |
| dataPath | Path to the JSON string of the merged data to use in the data workspace. Only required if commonTags is not set or empty. | Yes | data.json |

## Changes in 2.2.2
* Support populating multiarch image entities correctly

## Changes in 2.2.1
* Add support for server types of production-internal and stage-internal

## Changes in 2.2.0
* Add feature of pushing multi architecture images metadata to Pyxis

## Changes since 2.0.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 1.2.0
* Create a floating tag when tagPrefix is set
  * This is in addition to the tag tagPrefix-timestamp a.k.a. commonTag that we create in Pyxis now
* Update image used in the task
  * The new image supports multiple tags in the create_pyxis_image Python script

## Changes since 1.1.2
* Update image used in the task
  * When rhPush is true, now we'll create two entries in ContainerImage.repositories - one is the normal one and the other
    is the special one with registry="registry.access.redhat.com"

## Changes since 1.1.1
* Use the image digest when doing skopeo inspect
  * Without a digest, the `latest` tag was assumed. But if it was missing, the command would fail

## Changes since 1.1.0
* Update image used in the task
  * The new image contains fix for missing image_id field when creating the Pyxis Container Image object

## Changes since 1.0.0
* Add optional `rhPush` parameter
  * This will be used in the `rh-push-to-registry-redhat-io` to use the proper `registry` and `repository` values when
    creating the Container Image object in Pyxis. Also, the image will be marked as published.
* Add optional `commonTag` parameter
  * If set, the `tag` in the Pyxis Container Image object will be set to it


## Changes since 0.5
* The tag parameter is removed
  * The default tag is now provided by the 'images.defaultTag' key in the data JSON file as the pipeline parameter will
    no longer be passed.
  * dataPath parameter to point to the data JSON file in the data workspace was added.

## Changes since 0.4
* Update Tekton API to v1

## Changes since 0.3
* mappedSnapshot parameter was removed and snapshotPath parameter was added
  * Instead of passing a json string representing the snapshot, the snapshot spec should exist in the data workspace
    in the filename provided by snapshotPath.

## Changes since 0.2

* Use tag present in mapping file if present.
* The syntax for `taskRef.bundle` and `pipelineRef.bundle` is deprecated,
  bundles resolver is used with new format.

## Changes since 0.1

* Fix for incorrect snapshot param.
