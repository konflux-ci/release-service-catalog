# extract-binaries-from-image

Tekton task that extracts binaries to be released on github.com from an image.

The path to the directory inside the provided workspace where the binaries were
saved is provided as a result.

The binaries must be stored at the same `image_binaries_path` for each component
passed.

## Parameters

| Name                | Description                                                                | Optional | Default value |
|---------------------|----------------------------------------------------------------------------|----------|---------------|
| image_binaries_path | Path inside the image where the binaries to extract are stored             | Yes      | /releases     |
| snapshotPath        | Path to the JSON string of the mapped Snapshot spec in the data workspace  | No       | -             |
| subdirectory        | Subdirectory inside the workspace to be used for storing the binaries      | Yes      | ""            |
| dataPath            | Path to the JSON string of the merged data to use in the data workspace    | No       | -             |

## Changes in 2.1.3
* Add comprobation to only extract from the layer with the releases directory

## Changes in 2.1.2
* Fix typo in fetching DESIRED_COMPONENTS_LIST `content-gateway` -> `contentGateway`

## Changes in 2.1.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 2.1.0
* updated the base image used in this task

## Changes in 2.0.0
* support multiple components in snapshot

## Changes in 1.2.0
* updated the base image used in this task

## Changes in 1.1.0
* remove `snapshotPath` default value
