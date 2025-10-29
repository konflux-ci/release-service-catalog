# save-collectors-results

A tekton task that updates the passed CR status with the contents stored in the files in the resultsDir.

## Parameters

| Name                 | Description                                                                  | Optional | Default value |
|----------------------|------------------------------------------------------------------------------|----------|---------------|
| resourceType         | The type of resource that is being patched                                   | Yes      | release       |
| statusKey            | The top level key to overwrite in the resource status                        | Yes      | collectors    |
| resource             | The namespaced name of the resource to be patched                            | No       | -             |
| resultsDirPath       | The relative path in the workspace where the collectors results are saved to | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                        | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data        | Yes      | ca-bundle.crt |
