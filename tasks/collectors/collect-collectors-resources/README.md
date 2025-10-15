# collect-collectors-resources

Tekton task to collect collectors related resources.

The purpose of this task is to collect all the resources related with the collectors feature and supply
them to other tasks in the pipeline by creating json files for each resource. This task is similar
to collect-data but it only collects a subset of the resources. Specifically those related to collectors.

A task result is returned for each resource with the relative path to the stored JSON for it in the workspace.

## Parameters

| Name                   | Description                                                           | Optional | Default value |
|------------------------|-----------------------------------------------------------------------|----------|---------------|
| previousRelease        | The namespaced name of the previous Release                           | No       | -             |
| release                | The namespaced name of the Release                                    | No       | -             |
| collectorsResourceType | The type of resource that contains the collectors                     | Yes      | releaseplan   |
| collectorsResource     | The namespaced name of the resource that contains the collectors      | No       | -             |
| subdirectory           | Subdirectory inside the workspace to be used                          | Yes      | ""            |
| caTrustConfigMapName   | The name of the ConfigMap to read CA bundle data from                 | Yes      | trusted-ca    |
| caTrustConfigMapKey    | The name of the key in the ConfigMap that contains the CA bundle data | Yes      | ca-bundle.crt |
