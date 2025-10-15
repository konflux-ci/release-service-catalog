# cleanup-internal-requests

Tekton task to delete internal requests associated with a pipelinerun

## Parameters

| Name                 | Description                                                                    | Optional | Default value |
|----------------------|--------------------------------------------------------------------------------|----------|---------------|
| pipelineRunUid       | The uid of the current pipelineRun. It is only available at the pipeline level | No       | -             |
| caTrustConfigMapName | The name of the ConfigMap to read CA bundle data from                          | Yes      | trusted-ca    |
| caTrustConfigMapKey  | The name of the key in the ConfigMap that contains the CA bundle data          | Yes      | ca-bundle.crt |
