# validate-single-component

A tekton task that validates the snapshot only contains a 
single component. The task will fail otherwise.

## Parameters

| Name         | Description                                                        | Optional | Default value |
|--------------|--------------------------------------------------------------------|----------|---------------|
| snapshotPath | Path to the JSON string of the Snapshot spec in the data workspace | No       | -             |

## Changes in 0.5.0
* Updated the base image used in this task

## Changes in 0.4.0
* Updated the base image used in this task

## Changes in 0.3.0
* remove `snapshotPath` default value

## Changes in 0.1.0
* Updated hacbs-release/release-utils image to reference redhat-appstudio/release-service-utils image instead
