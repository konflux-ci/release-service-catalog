# extract-index-image

Extract the index image fields from the inputDataFile

The inputDataFile is a result from another task which includes the workspace name in it. Thus,
the workspace name for this task *must* be input.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| inputDataFile | File to read json data from | No | - |

## Changes since 0.1
- update Tekton API to v1