# cleanup-workspace

Tekton task to delete a given directory in a passed workspace and cleanup InternalRequests related to the current
PipelineRun.

## Parameters

| Name                 | Description                                                                    | Optional | Default value |
|----------------------|--------------------------------------------------------------------------------|----------|---------------|
| subdirectory         | The directory to remove within the workspace                                   | No       | -             |
| delay                | Time in seconds to delay the cleanup action                                    | Yes      | 60            |
| pipelineRunUid       | The uid of the current pipelineRun. It is only available at the pipeline level | Yes      | ""            |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                          | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data          | Yes      | ca-bundle.crt |
