# publish-pyxis-repository

Tekton task to mark all repositories in the mapped snapshot as published in Pyxis.
This is currently only meant to be used in the rh-push-to-registry-redhat-io pipeline,
so it will convert the values to the ones used for registry.redhat.io releases.
E.g. repository "quay.io/redhat-prod/my-product----my-image" will be converted to use
registry "registry.access.redhat.com" and repository "my-product/my-image" to identify
the right Container Registry object in Pyxis. The task also optionally
marks the repositories as source_container_image_enabled true if pushSourceContainer
is true in the data JSON.
Additionally, this task respects the `publish-on-push` flag. If `false`, then the task
does not publish the repository.



## Parameters

| Name         | Description                                                                                       | Optional | Default value      |
|--------------|---------------------------------------------------------------------------------------------------|----------|--------------------|
| server       | The server type to use. Options are 'production' and 'stage'                                      | Yes      | production         |
| pyxisSecret  | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert | No       | -                  |
| snapshotPath | Path to the JSON string of the mapped Snapshot spec in the data workspace                         | No       | -                  |
| dataPath     | Path to the JSON string of the merged data to use in the data workspace                           | No       | -                  |

## Changes in 1.1.0
* Updated the base image used in this task

## Changes in 1.0.0
* `images.pushSourceContainer` is no longer supported

## Changes in 0.6.0
* Updated the base image used in this task

## Changes in 0.5.0
* Add support for checking the `mapping` key for `pushSourceContainer`
  * Can be per component or in the `mapping.defaults` section
  * The legacy location of `images.pushSourceContainer` will be removed in a future version

## Changes in 0.4.0
* Add option to skip publishing via `skipRepoPublishing` flag in the data file

## Changes in 0.3.0
* remove `dataPath` and `snapshotPath` default values

## Changes in 0.2.2
* Add support for server types of production-internal and stage-internal

## Changes in 0.2.1
* The task now respects the `publish-on-push` flag. If `false`, then the task
does not publish the repository.

## Changes in 0.2.0
* If a data JSON is provided and images.pushSourceContainer is set to true inside it, a call is made
to mark the repository as source_container_image_enabled true

## Changes in 0.0.2
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.0.1
* Minor change to logging to provide more context about the pyxis repo request on failure
