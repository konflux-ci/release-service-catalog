# run-collectors

Tekton task to run the collectors defined in a resource passed as parameter. The results are saved in the
resultsDir, one file per collector.

## Parameters

| Name                         | Description                                                                             | Optional | Default value |
|------------------------------|-----------------------------------------------------------------------------------------|----------|---------------|
| collectorsPath               | Path to the JSON string of the resource containing the collectors in the data workspace | No       | -             |
| collectorsResourceType       | The type of resource that contains the collectors                                       | No       | -             |
| resultsDir                   | The relative path in the workspace to save the collector results to                     | No       | -             |
| collectorsRepository         | Git repository where the collectors will be defined                                     | No       | -             |
| collectorsRepositoryRevision | Git repository revision                                                                 | Yes      | main          |
| releasePath                  | Path to the json data file of the current in-progress Release                           | No       | -             |
| previousReleasePath          | Path to the json data file of the previous successful Release prior to the current one  | No       | -             |
| caTrustConfigMapName         | The name of the ConfigMap to read CA bundle data from                                   | Yes      | trusted-ca    |
| caTrustConfigMapKey          | The name of the key in the ConfigMap that contains the CA bundle data                   | Yes      | ca-bundle.crt |
