# filter-already-released-advisory-images-task

Filters out images from a snapshot if they are already published in an advisory
stored in the GitLab advisory repo. Returns a list of component names
that still need to be released (i.e., not found in any advisory).

## Parameters

| Name                           | Description                                                                                | Optional | Default value |
|--------------------------------|--------------------------------------------------------------------------------------------|----------|---------------|
| transformedSnapshot            | Base64 string of gzipped JSON representation of architecture-specific images from snapshot | No       | -             |
| origin                         | The origin workspace for the release CR                                                    | No       | -             |
| advisory_secret_name           | Name of the secret containing advisory metadata                                            | No       | -             |
| internalRequestPipelineRunName | Name of the PipelineRun that requested this task                                           | No       | -             |
| caTrustConfigMapName           | The name of the ConfigMap to read CA bundle data from                                      | Yes      | trusted-ca    |
| caTrustConfigMapKey            | The name of the key in the ConfigMap that contains the CA bundle data                      | Yes      | ca-bundle.crt |
