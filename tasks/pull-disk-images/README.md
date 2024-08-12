# pull-disk-images

Tekton task to pull disk images from quay using oras pull.

The disk images are stored in a workspace, and they are expected to be quite large. Due to this,
the data workspace that is attached to this task should be quite large, potentially 100s of GBs.

## Parameters

| Name            | Description                                                                  | Optional | Default value |
|-----------------|------------------------------------------------------------------------------|----------|---------------|
| snapshotPath    | Path to the JSON string of the Snapshot spec in the data workspace           | No       | -             |
| concurrentLimit | The maximum number of images to be pulled at once                            | Yes      | 3             |

## Changes in 0.2.0
* Updated the base image used in this task
