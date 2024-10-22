# create-internal-request

Creates an InternalRequest resource to call IIB service

## Parameters

| Name                  | Description                                                   | Optional | Default value |
|-----------------------|------------------------------------------------------------------|----------|---------------|
| pipelineRunName       | The name of the Parent PipelineRun for this task                 | No       | `ir-$(context.pipelineRun.name)` |
| request               | Internal pipeline request name                                   | No       | -             |
| internalRequestParams | Internal Request parameters                                      | No       | -             |
| dataPath              | Path to the JSON file of the merged data to use in the data workspace | No  | -             |  
| inputDataFile         | Optional file to read data from                                  | Yes      | ""            |
| updateGenericResult   | Should the task update the genericResult result                  | Yes      | "false"       |
| requestUpdateTimeout  | Max seconds to wait until the status is updated                  | Yes      | 360           |
| subdirectory          | Subdirectory inside the workspace to be used                     | Yes      | ""            |

## Changelog

## Changes in 0.13.1
* Fix linting issues in create-internal-request task

## Changes in 0.13.0
* Updated the base image used in this task

## Changes in 0.12.0
* Updated the base image used in this task

## Changes in 0.11.0
* remove `dataPath` default value

## Changes in 0.9.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes in 0.8
* add parameter `dataPath` to support data JSON file
* add step `merge-internal-request-parameters` to merge data from data.json
  with the internal-request parameters
* modify step `prepare-internal-request` to read the data from `data.json`

## Changes in 0.7
* update Tekton API to v1

## Changes in 0.6
* add new subdirectory parameter to be used for storing of results file
    * this will enable us to clean up only the current pipelinerun's
      data in the fbc-release pipeline
* changes the task step `watch-internal-request-status` to check for
  `.status.condition[0].reason` instead of `.status.condition[0].status` to determine
  if the request has Succeeded of Failed.

## Changes in 0.5
* adds `updateGenericResult` parameter to control whether the `genericResult`
  result is updated
* adds `genericResult` to store data read from the `genericResult` status message
  from an `InternalRequest`
* updates `release-base-image` image to latest version

## Changes in 0.4
* full rewrite to accept dynamic parameters

## Changes in 0.3
* removes the additional logging
* removes `resolvedIndexImage` and `resolvedFromIndexImage` results
  as now the FBC-Release Pipeline uses `requestResults` to read required values.

## Changes in 0.2
* adds additional logging messages

## Changes in 0.1
* adds `resolvedIndexImage` result
* adds params `requestUpdateTimeout` and `buildTimeoutSeconds`
