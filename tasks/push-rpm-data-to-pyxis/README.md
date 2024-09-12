# push-rpm-data-to-pyxis

Tekton task that extracts all rpms from the sboms and pushes them to Pyxis as an RPM Manifest.
In addition, it will also update ContainerImage.content_sets field in Pyxis to include
all repository_id strings found in rpm purl strings in the sboms.

## Parameters

| Name            | Description                                                                                         | Optional | Default value |
|-----------------|-----------------------------------------------------------------------------------------------------|----------|---------------|
| pyxisJsonPath   | Path to the JSON string of the saved Pyxis data in the data workspace                               | No       | -             |
| pyxisSecret     | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert   | No       | -             |
| server          | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'. | Yes      | production    |
| concurrentLimit | The maximum number of images to be processed at once                                                | Yes      | 4             |

## Changes in 1.0.0
* Renamed task from `push-rpm-manifest-to-pyxis` to `push-rpm-data-to-pyxis`
* Updated the image used in this task
  * The `upload_rpm_manifest` is renamed to `upload_rpm_data` and on top of RPM Manifest,
    it also updates the ContainerImage.content_sets field in Pyxis

## Changes in 0.4.4
* Updated the base image used in this task
  * The new image contains an updated upload_rpm_manifest script that will retry the POST
    request if it fails with error code 504

## Changes in 0.4.3
* Create new docker config for each `cosign download sbom` call
  * It only contains an entry for the specific image
  * This is to fix a bug with partial oci auth matches

## Changes in 0.4.2
* fixed a bug that would treat a multiarch image containing just one arch as a plain single arch image

## Changes in 0.4.1
* updated the base image used in this task
  * the new image contains an updated upload_rpm_manifest script with nvra and summary
    fields populated for each rpm item

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.1
* enabled verbose logging for the upload_rpm_manifest script

## Changes in 0.2.0
* updated the base image used in this task

## Changes in 0.1.2
* add support for production-internal and stage-internal

## Changes in 0.1.1
* multi-arch images are now properly supported
