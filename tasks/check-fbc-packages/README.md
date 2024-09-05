# check-fbc-packages

Task to check that the packages being shipped in an fbc contribution are in the allow list provided in the dataPath.

## Parameters

| Name           | Description                                                               | Optional | Default value |
|----------------|---------------------------------------------------------------------------|----------|---------------|
| snapshotPath   | Path to the JSON string of the mapped Snapshot spec in the data workspace | No       | -             |
| dataPath       | Path to the JSON string of the merged data to use in the data workspace   | No       | -             |

## Changes in 0.4.1
* fix linting issues in check-fbc-package task

## Changes in 0.4.0
* updated the base image used in this task

## Changes in 0.3.0
* updated the base image used in this task

## Changes in 0.2.0
* remove default values of `snapshotPath` and `dataPath` parameters
