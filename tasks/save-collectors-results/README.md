# save-collectors-results

A tekton task that updates the passed CR status with the contents stored in the files in the resultsDir.

## Parameters

| Name           | Description                                                                                                          | Optional | Default value |
|----------------|----------------------------------------------------------------------------------------------------------------------|----------|---------------|
| resourceType   | The type of resource that is being patched                                                                           | Yes      | release       |
| statusKey      | The top level key to overwrite in the resource status                                                                | Yes      | collectors    |
| resource       | The namespaced name of the resource to be patched                                                                    | No       | -             |
| resultsDirPath | Path to the directory containing the result files in the data workspace which will be added to the resource's status | No       | -             |
