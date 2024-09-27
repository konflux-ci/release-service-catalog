# update-cr-status

A tekton task that updates the passed CR status with the contents stored in the files in the resultsDir.

## Parameters

| Name           | Description                                                                                                          | Optional | Default value |
|----------------|----------------------------------------------------------------------------------------------------------------------|----------|---------------|
| resourceType   | The type of resource that is being patched                                                                           | Yes      | release       |
| statusKey      | The top level key to overwrite in the resource status                                                                | Yes      | artifacts     |
| resource       | The namespaced name of the resource to be patched                                                                    | No       | -             |
| resultsDirPath | Path to the directory containing the result files in the data workspace which will be added to the resource's status | No       | -             |

## Changes in 0.3.1
* Fix shellcheck/checkton linting issues in the task and tests

## Changes in 0.3.0
* Updated the base image used in this task

## Changes in 0.2.0
* Updated the base image used in this task
