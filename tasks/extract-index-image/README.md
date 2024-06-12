# extract-index-image

Extract the index image fields from the inputDataFile

The inputDataFile is a result from another task which includes the workspace name in it. Thus,
the workspace name for this task *must* be input.

## Parameters

| Name | Description | Optional | Default value |
|------|-------------|----------|---------------|
| inputDataFile | File to read json data from | No | - |

## Changes in 0.4.0
- Updated the base image used in this task

## Changes since 0.2.0
- Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead

## Changes since 0.1
- update Tekton API to v1
