# create-internal-request

Creates an InternalRequest resource to call IIB service

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| pipelineRunName | The name of the Parent PipelineRun for this task | No | `ir-$(context.pipelineRun.name)` |
| request | Internal pipeline request name | No | |
| params | Internal Request parameters | No | |
| inputDataFile | Optional file to read data from | Yes | "" |
| updateGenericResult | Should the task update the genericResult result  | Yes | "false" |
| requestUpdateTimeout | Max seconds to wait until the status is updated | Yes | 360 |

## Changelog

### changes since 0.6
- add new subdirectory parameter to be used for storing of results file
    - this will enable us to clean up only the current pipelinerun's
      data in the fbc-release pipeline
- changes the task step `watch-internal-request-status` to check for
  `.status.condition[0].reason` instead of `.status.condition[0].status` to determine
  if the request has Succeeded of Failed.

### changes since 0.5
- adds `updateGenericResult` parameter to control whether the `genericResult`
  result is updated
- adds `genericResult` to store data read from the `genericResult` status message
  from an `InternalRequest`
- updates `release-base-image` image to latest version

### changes since 0.4
- full rewrite to accept dynamic parameters

### changes since 0.3
- removes the additional logging
- removes `resolvedIndexImage` and `resolvedFromIndexImage` results
  as now the FBC-Release Pipeline uses `requestResults` to read required values.

### changes since 0.2
- adds additional logging messages

### changes since 0.1
- adds `resolvedIndexImage` result
- adds params `requestUpdateTimeout` and `buildTimeoutSeconds`
