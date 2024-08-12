# prepare-fbc-release

A tekton task to prepare FBC Release by collecting a valid
OCP version for each component from given
containerImage(fbcFragment) in the snapshot, and update
the fromIndex, targetIndex and binaryImage with collected
OCP version and store updated values to snapshot respective
to each component, so other task can use them.

## Parameters

| Name         | Description                                                             | Optional | Default value      |
|--------------|-------------------------------------------------------------------------|----------|--------------------|
| snapshotPath | Path to the JSON string of the Snapshot spec in the data workspace      | No       | -                  |
| dataPath     | Path to the JSON string of the merged data to use in the data workspace | No       | -                  |

## Changes in 1.3.0
* updated the base image used in this task

## Changes in 1.2.0
* updated the base image used in this task

## Changes in 1.1.0
* remove `dataPath` and `snapshotPath` default values
