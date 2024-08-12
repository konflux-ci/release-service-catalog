# publish-index-image

Publish a built FBC index image using skopeo

## Parameters

| Name           | Description                                                                               | Optional | Default value |
|----------------|-------------------------------------------------------------------------------------------|----------|---------------|
| dataPath       | Path to the JSON string of the merged data to use in the data workspace                   | No       | -             |
| sourceIndex    | Pullspec to pull the image from                                                           | No       | -             |
| targetIndex    | Pullspec to push the image to                                                             | No       | -             |
| retries        | Number of skopeo retries                                                                  | Yes      | 0             |
| requestTimeout | Max seconds waiting for the status update                                                 | Yes      | 360           |
| buildTimestamp | Build timestamp for the publishing image                                                  | No       | -             |
| pipelineRunUid | The uid of the current pipelineRun. Used as a label value when creating internal requests | No       | -             |

## Changes in 3.3.0
* updated the base image used in this task

## Changes in 3.2.0
* updated the base image used in this task

## Changes in 3.1.0
* remove `dataPath` default value

## Changes in 3.0.0
* The internalrequest CR is created with a label specifying the pipelinerun uid with the new pipelineRunUid parameter
  * This change comes with a bump in the image used for the task

## Changes in 2.0.0
* Add the parameter `buildTimestamp` to push also a timestamp-based tag

## Changes in 1.0.0
* Refactor to use the `internal-request` script

## Changes in 0.3.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.2
* update Tekton API to v1

## Changes in 0.1
* adds `inputDataFile` parameter to read the image source from it
