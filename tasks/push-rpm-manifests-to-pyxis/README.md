# push-rpm-manifests-to-pyxis

Tekton task that extracts all rpms from the sboms and pushes them to Pyxis as an RPM Manifest.

## Parameters

| Name            | Description                                                                                         | Optional | Default value |
|-----------------|-----------------------------------------------------------------------------------------------------|----------|---------------|
| pyxisJsonPath   | Path to the JSON string of the saved Pyxis data in the data workspace                               | No       | -             | 
| pyxisSecret     | The kubernetes secret to use to authenticate to Pyxis. It needs to contain two keys: key and cert   | No       | -             |
| server          | The server type to use. Options are 'production','production-internal,'stage-internal' and 'stage'. | Yes      | production    |
| concurrentLimit | The maximum number of images to be processed at once                                                | Yes      | 4             |

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
